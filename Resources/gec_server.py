import sys
import json
import time
import threading
import logging
import gc

# Fallback imports
try:
    import litellm
    # Optional: Suppress litellm verbose logging
    litellm.suppress_debug_info = True
except ImportError:
    litellm = None

try:
    from llama_cpp import Llama
except ImportError:
    Llama = None

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a highly advanced, strict text editor.
Your ONLY task is to take the user's input text and output the exact same text with corrected grammar, spelling, and punctuation.
CRITICAL RULES:
1. NEVER answer questions. If the user writes a question, you must only correct its grammar.
2. NEVER converse or chat.
3. NEVER add explanations, apologies, or markdown formatting.
4. ONLY output the corrected text. Nothing else."""

class UniversalOrchestrator:
    def __init__(self):
        self.local_model = None
        self.local_model_path = None
        self.llm_lock = threading.Lock()
        self.sts_lock = threading.Lock()
        
        # Start Silent Pre-Loader thread
        self.preload_thread = threading.Thread(target=self._silent_preload, daemon=True)
        self.preload_thread.start()

    def _silent_preload(self):
        logger.info("Silent Pre-Loader: Warming up engines in the background...")
        try:
            import subprocess
            
            # Check if backend type is 'local'
            backend_result = subprocess.run(["defaults", "read", "com.mactoys.inputmethod.MacToys", "gecBackendType"], capture_output=True, text=True)
            backend_type = backend_result.stdout.strip()
            
            # 1. Warm up Anti-Hallucination Judge (loads llama.cpp GGUF)
            with self.sts_lock:
                if not hasattr(self, 'sts_model'):
                    import os
                    judge_path = os.path.join(os.path.dirname(__file__), 'all-MiniLM-L6-v2-q8_0.gguf')
                    if os.path.exists(judge_path) and Llama is not None:
                        self.sts_model = Llama(
                            model_path=judge_path,
                            embedding=True,
                            verbose=False
                        )
                        logger.info("Silent Pre-Loader: Anti-Hallucination Judge loaded (GGUF).")
            
            # Check if auto-load on startup is enabled
            autoload_result = subprocess.run(["defaults", "read", "com.mactoys.inputmethod.MacToys", "gecLoadOnStartup"], capture_output=True, text=True)
            auto_load = autoload_result.stdout.strip()
            # If not explicitly 0 (false), we assume true (default)
            if auto_load == "0":
                logger.info("Silent Pre-Loader: 'Load on Startup' is disabled. Skipping local model load.")
                return
            
            # 2. Read UserDefaults to get the local model path and warm it up
            result = subprocess.run(["defaults", "read", "com.mactoys.inputmethod.MacToys", "gecModelPath"], capture_output=True, text=True)
            if result.returncode == 0:
                path = result.stdout.strip()
                if path and path.endswith('.gguf'):
                    # Warm up Llama CPP & Metal
                    self._load_local_model(path)
                    logger.info("Silent Pre-Loader: Local model warmed up into macOS Virtual Memory.")
        except Exception as e:
            logger.error(f"Silent Pre-Loader Error: {e}")

    def _load_local_model(self, path):
        with self.llm_lock:
            if self.local_model_path == path and self.local_model is not None:
                return  # Already loaded
                
            if Llama is None:
                raise RuntimeError("llama-cpp-python is not installed.")
                
            logger.info(f"Loading local model from {path}...")
            self.local_model = Llama(
                model_path=path,
                n_gpu_layers=-1, # Use all available GPU layers (Metal on Mac)
                n_ctx=2048,
                verbose=False # Suppress llama.cpp C-level logging spam
            )
            self.local_model_path = path
            logger.info("Local model loaded successfully.")

    def process_request(self, payload):
        req_id = payload.get("id", "unknown")
        text = payload.get("text", "")
        backend_type = payload.get("backend_type", "api") # default to api for safety
        instruction = payload.get("instruction", "").strip()
        
        if not text.strip():
            return {"id": req_id, "corrected": ""}

        if instruction:
            # Custom instruction mode (Rephrase, Rewrite, Tone, etc.)
            # We use a few-shot example built directly into the user/assistant roles.
            # This avoids the "system" role crash on Gemma and forces it to understand 
            # it is editing, not conversing.
            messages_attempt_1 = [
                {
                    "role": "user", 
                    "content": f"You are a strict text editing tool. You MUST rewrite the text according to this instruction: '{instruction}'\n\nCRITICAL RULES:\n1. NEVER answer or reply to questions.\n2. ONLY output the rewritten text.\n\nText to rewrite:\nwhere is the store?"
                },
                {
                    "role": "assistant", 
                    "content": "Could you please direct me to the store?"
                },
                {
                    "role": "user", 
                    "content": f"Text to rewrite:\n{text}"
                }
            ]
            # No retry loop for custom instructions, just do it once
            try:
                if backend_type == "api":
                    result_text = self._handle_api(payload, messages_attempt_1)
                elif backend_type == "local":
                    result_text = self._handle_local(payload, messages_attempt_1)
                else:
                    raise ValueError(f"Unknown backend_type: {backend_type}")
                
                result_text = result_text.strip()
                    
                # Skip hallucination check because custom instructions change meaning/phrasing on purpose
                return {"id": req_id, "corrected": result_text}
            except Exception as e:
                logger.error(f"Error processing request: {e}")
                return {"id": req_id, "error": str(e)}

        # Grammar Fix Mode (Default)
        # Attempt 1: Standard few-shot examples to force the model to behave purely as an editor
        messages_attempt_1 = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": "I has went to the store"},
            {"role": "assistant", "content": "I went to the store."},
            {"role": "user", "content": "what is your name."},
            {"role": "assistant", "content": "What is your name?"},
            {"role": "user", "content": "hello how r u"},
            {"role": "assistant", "content": "Hello, how are you?"},
            {"role": "user", "content": text}
        ]
        
        # Attempt 2: Strict retry prompt because it got confused
        messages_attempt_2 = [
            {"role": "system", "content": SYSTEM_PROMPT + "\n\nWARNING: Your previous attempt completely failed because you hallucinated a response, hallucinated new information, or completely changed the original meaning of the text. You MUST strictly act as a grammar corrector. DO NOT answer questions. DO NOT add new information. JUST fix the grammar. If it is already fine, return it exactly as is."},
            {"role": "user", "content": f"Please try again and STRICTLY fix the grammar without changing the core meaning of this text:\n\n{text}"}
        ]

        try:
            for attempt, messages in enumerate([messages_attempt_1, messages_attempt_2]):
                if backend_type == "api":
                    corrected_text = self._handle_api(payload, messages)
                elif backend_type == "local":
                    corrected_text = self._handle_local(payload, messages)
                else:
                    raise ValueError(f"Unknown backend_type: {backend_type}")
                    
                corrected_text = corrected_text.strip()
                
                # --- POST-CHECK: Anti-Hallucination Judge (BOTH API & LOCAL) ---
                is_hallucination, sim_score = self._check_hallucination(text, corrected_text)
                
                if not is_hallucination:
                    return {"id": req_id, "corrected": corrected_text}
                
                logger.warning(f"Attempt {attempt + 1}: Hallucination Blocked! Score: {sim_score:.2f}. Text: {corrected_text}")
                
                if attempt == 1: # Failed both attempts
                    return {"id": req_id, "error": f"AI Hallucination Detected on retry (Similarity: {int(sim_score*100)}%). Change rejected to protect meaning."}
            
        except Exception as e:
            logger.error(f"Error processing request: {e}")
            return {"id": req_id, "error": str(e)}

    def cos_sim(self, a, b):
        import math
        dot_product = sum(x * y for x, y in zip(a, b))
        magnitude_a = math.sqrt(sum(x * x for x in a))
        magnitude_b = math.sqrt(sum(x * x for x in b))
        if magnitude_a * magnitude_b == 0:
            return 0.0
        return dot_product / (magnitude_a * magnitude_b)

    def _check_hallucination(self, original, corrected):
        # Lazy load the tiny STS model to save startup time
        with self.sts_lock:
            if not hasattr(self, 'sts_model'):
                logger.info("Loading Anti-Hallucination Judge (Llama.cpp MiniLM)...")
                try:
                    import os
                    judge_path = os.path.join(os.path.dirname(__file__), 'all-MiniLM-L6-v2-q8_0.gguf')
                    if not os.path.exists(judge_path):
                        logger.error("MiniLM GGUF not found. Skipping judge.")
                        return False, 1.0
                    self.sts_model = Llama(
                        model_path=judge_path,
                        embedding=True,
                        verbose=False
                    )
                    logger.info("Judge loaded.")
                except Exception as e:
                    logger.error(f"Failed to load judge: {e}")
                    return False, 1.0

        if not original.strip() or not corrected.strip():
            return False, 1.0

        try:
            emb_orig = self.sts_model.create_embedding(original)["data"][0]["embedding"]
            emb_corr = self.sts_model.create_embedding(corrected)["data"][0]["embedding"]
            
            sim_score = self.cos_sim(emb_orig, emb_corr)
            
            # For very short sentences (under 4 words), cosine similarity swings wildly.
            # E.g., 'i has went' -> 'I went.' is only 64%.
            # True hallucinations (e.g. 'I am a text editor') score < 10%.
            # We lower the strict threshold to 50% to prevent false positives.
            threshold = 0.50
            if len(original.split()) <= 3:
                threshold = 0.40 # Even more lenient for 1-3 word phrases
            
            if sim_score < threshold:
                return True, sim_score
            return False, sim_score
        except Exception as e:
            logger.error(f"Error in Anti-Hallucination Judge: {e}")
            return False, 1.0

    def _handle_api(self, payload, messages):
        if litellm is None:
            raise RuntimeError("litellm is not installed.")
            
        model = payload.get("model")
        api_key = payload.get("api_key")
        
        if not model:
            raise ValueError("API request missing 'model' (e.g., 'gpt-4o' or 'gemini/gemini-1.5-flash')")
        if not api_key:
            raise ValueError("API request missing 'api_key'")

        # litellm handles unified formats
        response = litellm.completion(
            model=model,
            messages=messages,
            api_key=api_key,
            temperature=0.1
        )
        return response.choices[0].message.content

    def _handle_local(self, payload, messages):
        model_path = payload.get("model_path")
        if not model_path:
            raise ValueError("Local request missing 'model_path' (path to .gguf file)")
            
        self._load_local_model(model_path)
        
        try:
            response = self.local_model.create_chat_completion(
                messages=messages,
                temperature=0.1
            )
        except Exception as e:
            error_str = str(e).lower()
            if "system role not supported" in error_str or "system" in error_str:
                logger.warning("System role not supported by this model (e.g., Gemma). Merging system prompt into user prompt.")
                new_messages = []
                system_content = ""
                for msg in messages:
                    if msg["role"] == "system":
                        system_content += msg["content"] + "\n\n"
                    elif msg["role"] == "user" and system_content:
                        new_messages.append({"role": "user", "content": system_content + msg["content"]})
                        system_content = "" # Only merge into the first user prompt
                    else:
                        new_messages.append(msg)
                
                response = self.local_model.create_chat_completion(
                    messages=new_messages,
                    temperature=0.1
                )
            else:
                raise e
        
        return response["choices"][0]["message"]["content"]


def main():
    orchestrator = UniversalOrchestrator()
    print(json.dumps({"status": "ready", "message": "Universal Orchestrator Started"}), flush=True)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
            
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            print(json.dumps({"error": "Invalid JSON"}), flush=True)
            continue
            
        if "command" in payload:
            cmd = payload["command"]
            if cmd == "shutdown":
                sys.exit(0)
            elif cmd == "load_local":
                import subprocess
                result = subprocess.run(["defaults", "read", "com.mactoys.inputmethod.MacToys", "gecModelPath"], capture_output=True, text=True)
                path = result.stdout.strip()
                if path and path.endswith('.gguf'):
                    try:
                        orchestrator._load_local_model(path)
                        print(json.dumps({"status": "ready", "message": "Local model loaded successfully"}), flush=True)
                    except Exception as e:
                        print(json.dumps({"error": f"Failed to load: {e}"}), flush=True)
            elif cmd == "unload_local":
                with orchestrator.llm_lock:
                    if orchestrator.local_model is not None:
                        del orchestrator.local_model
                    orchestrator.local_model = None
                    orchestrator.local_model_path = None
                
                # Also delete the Anti-Hallucination Judge to free RAM
                with orchestrator.sts_lock:
                    if hasattr(orchestrator, 'sts_model'):
                        del orchestrator.sts_model
                        
                import gc
                gc.collect()
                    
                print(json.dumps({"status": "ready", "message": "Local model unloaded from RAM"}), flush=True)
            continue
            
        result = orchestrator.process_request(payload)
        print(json.dumps(result), flush=True)

if __name__ == "__main__":
    main()
