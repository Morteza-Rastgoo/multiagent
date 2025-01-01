import os
import sys
import speech_recognition as sr
from gtts import gTTS
import playsound
import tempfile
import time
from dotenv import load_dotenv
from langchain.llms import Ollama
from langchain.chains import LLMChain
from langchain.prompts import PromptTemplate
from langchain.tools import DuckDuckGoSearchRun, Tool
from langchain.agents import initialize_agent, AgentType
from langchain.memory import ConversationBufferMemory
from langchain.callbacks import get_openai_callback
import interpreter
import logging
import json
import re

# Set up logging
logging.basicConfig(level=logging.INFO,
                   format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Load environment variables
if not os.path.exists('config/config.env'):
    raise RuntimeError("Configuration file not found. Please run install.sh first")
load_dotenv('config/config.env')

class MultiAgent:
    def __init__(self):
        try:
            # Initialize speech components
            self.recognizer = sr.Recognizer()
            self.temp_dir = tempfile.mkdtemp()
            self.audio_counter = 0
            
            # Test microphone
            with sr.Microphone() as source:
                logger.info("Testing microphone...")
                self.recognizer.adjust_for_ambient_noise(source, duration=1)
            
            # Initialize components
            logger.info("Initializing components...")
            self.setup_models()
            self.setup_memory()
            self.setup_tools()
            self.setup_agents()
            self.setup_interpreter()
            
            logger.info("Initialization complete")
            
        except Exception as e:
            logger.error(f"Initialization error: {str(e)}")
            raise

    def setup_models(self):
        """Initialize language models with proper configuration"""
        try:
            base_url = "http://localhost:11434"
            self.models = {
                'chat': Ollama(
                    model=os.getenv('CHAT_MODEL', 'neural-chat:7b-v3.3-q4_K_M'),
                    base_url=base_url,
                    temperature=float(os.getenv('TEMPERATURE', '0.7')),
                    timeout=60  # Increased timeout
                ),
                'code': Ollama(
                    model=os.getenv('CODING_MODEL', 'codellama:7b-instruct-q4_K_M'),
                    base_url=base_url,
                    temperature=0.3,
                    timeout=60  # Increased timeout
                )
            }
            logger.info("Models initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize models: {str(e)}")
            raise

    def setup_memory(self):
        """Initialize conversation memory"""
        try:
            memory_size = int(os.getenv('MEMORY_SIZE', '10'))
            self.memory = {
                'chat': ConversationBufferMemory(
                    memory_key="chat_history",
                    return_messages=True,
                    output_key="output",
                    k=memory_size
                ),
                'code': ConversationBufferMemory(
                    memory_key="code_history",
                    return_messages=True,
                    output_key="output",
                    k=memory_size
                )
            }
            logger.info("Memory initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize memory: {str(e)}")
            raise

    def setup_tools(self):
        """Initialize tools for enhanced reasoning"""
        try:
            def enhanced_reasoning(query):
                """Enhanced reasoning with structured analysis"""
                try:
                    # Create a structured analysis prompt
                    analysis_prompt = f"""Please help me analyze and answer this query: {query}

                    Follow these steps:
                    1. Break down the key aspects of the query
                    2. Apply logical reasoning and analysis
                    3. Draw from your knowledge to provide comprehensive insights
                    4. Consider multiple perspectives
                    5. Provide concrete examples when relevant
                    6. Acknowledge any limitations in your knowledge
                    7. Suggest related topics for deeper understanding

                    Respond in a clear, well-structured format."""

                    # Use the chat model for analysis
                    response = self.models['chat'].invoke(analysis_prompt)
                    return response
                except Exception as e:
                    logger.error(f"Analysis error: {str(e)}")
                    return "I encountered an error in my analysis. Let me try a different approach."

            self.tools = [
                Tool(
                    name="Enhanced Reasoning",
                    func=enhanced_reasoning,
                    description="Provides in-depth analysis and comprehensive answers using structured reasoning and knowledge synthesis."
                )
            ]
            logger.info("Tools initialized successfully with enhanced reasoning capabilities")
                
        except Exception as e:
            logger.error(f"Failed to initialize tools: {str(e)}")
            self.tools = []

    def setup_agents(self):
        """Initialize conversation agents with enhanced reasoning"""
        try:
            # Chat agent with Perplexity-like capabilities
            self.agents = {
                'chat': initialize_agent(
                    tools=self.tools,
                    llm=self.models['chat'],
                    agent=AgentType.CHAT_CONVERSATIONAL_REACT_DESCRIPTION,
                    memory=self.memory['chat'],
                    verbose=True,
                    handle_parsing_errors=True,
                    max_iterations=5,
                    early_stopping_method="generate",
                    agent_kwargs={
                        "system_message": """You are an advanced AI assistant that provides comprehensive, well-reasoned responses similar to Perplexity AI.

                        For each query:
                        1. Break down complex topics into understandable components
                        2. Provide detailed explanations with logical reasoning
                        3. Include relevant examples and analogies
                        4. Consider multiple perspectives and approaches
                        5. Acknowledge uncertainties and limitations
                        6. Suggest related concepts for deeper understanding
                        7. Maintain a clear and engaging conversational style
                        8. Support answers with structured reasoning
                        9. Adapt the depth of analysis to the query complexity
                        
                        You can understand and respond in both English and Persian, maintaining the same level of analytical depth in both languages."""
                    }
                ),
                'code': initialize_agent(
                    tools=[],  # Code agent focuses on programming
                    llm=self.models['code'],
                    agent=AgentType.CHAT_CONVERSATIONAL_REACT_DESCRIPTION,
                    memory=self.memory['code'],
                    verbose=True,
                    handle_parsing_errors=True,
                    max_iterations=2,
                    agent_kwargs={
                        "system_message": """You are an expert programmer assistant.
                        When writing or reviewing code:
                        1. Follow best practices and coding standards
                        2. Include proper error handling
                        3. Write clear documentation
                        4. Consider performance and efficiency
                        5. Test thoroughly before providing solutions"""
                    }
                )
            }
            logger.info("Agents initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize agents: {str(e)}")
            raise
    
    def setup_interpreter(self):
        """Configure the code interpreter"""
        try:
            interpreter.reset()
            interpreter.auto_run = False  # Don't auto-run code for safety
            interpreter.max_tokens = int(os.getenv('MAX_TOKENS', '2048'))
            interpreter.temperature = 0.3
            
            # Configure the model
            interpreter.model = f"ollama/{os.getenv('CODING_MODEL', 'codellama:7b-instruct-q4_K_M')}"
            interpreter.api_base = "http://localhost:11434"
            
            # Set up a more focused system message
            interpreter.system_message = """You are a Python programming expert. When asked to write code:
            1. Write clear, well-documented Python code
            2. Include error handling
            3. Add helpful comments
            4. Provide usage examples
            5. Explain how to run the code
            
            Always create complete, runnable scripts that can be saved to a file and executed."""
            
            logger.info("Interpreter configured successfully")
        except Exception as e:
            logger.error(f"Failed to configure interpreter: {str(e)}")
            raise
    
    def listen(self):
        max_retries = 3
        for attempt in range(max_retries):
            try:
                with sr.Microphone() as source:
                    print("\nListening...")
                    # Adjust for ambient noise before each listen
                    self.recognizer.adjust_for_ambient_noise(source, duration=0.5)
                    audio = self.recognizer.listen(source, timeout=10, phrase_time_limit=10)
                    
                    # Try to detect language
                    try:
                        text = self.recognizer.recognize_google(audio)
                        print(f"You said: {text}")
                        return text
                    except:
                        # Fallback to specific languages if automatic detection fails
                        for lang in ['en-US', 'fa-IR']:
                            try:
                                text = self.recognizer.recognize_google(audio, language=lang)
                                print(f"You said ({lang}): {text}")
                                return text
                            except:
                                continue
                        raise
                    
            except sr.WaitTimeoutError:
                print("No speech detected. Please try again.")
            except sr.UnknownValueError:
                print("Sorry, I couldn't understand that. Please try again.")
            except sr.RequestError as e:
                print(f"Could not request results; {e}")
            except Exception as e:
                print(f"Error: {str(e)}")
            
            if attempt < max_retries - 1:
                print(f"Retrying... ({attempt + 1}/{max_retries})")
                time.sleep(1)
        
        return None

    def speak(self, text):
        print(f"\nAI: {text}")
        max_retries = 3
        for attempt in range(max_retries):
            try:
                # Detect language for TTS
                lang = 'en' if any(ord(c) < 128 for c in text) else 'fa'
                
                # Create temporary file for audio
                self.audio_counter += 1
                temp_file = os.path.join(self.temp_dir, f'speech_{self.audio_counter}.mp3')
                
                # Generate speech
                tts = gTTS(text=text, lang=lang)
                tts.save(temp_file)
                
                # Play audio
                playsound.playsound(temp_file)
                
                # Clean up
                try:
                    os.remove(temp_file)
                except:
                    pass
                    
                return
                    
            except Exception as e:
                logger.error(f"Speech error (attempt {attempt + 1}/{max_retries}): {str(e)}")
                if attempt == max_retries - 1:
                    logger.warning("Failed to generate speech, continuing with text only")
                else:
                    time.sleep(1)

    def process_command(self, command):
        if not command:
            return "I didn't catch that. Could you please try again?"
            
        try:
            # Check if it's a code-related query
            code_keywords = ['code', 'program', 'script', 'function', 'debug', 'run', 'execute', 'write', 'create']
            is_code_query = any(keyword in command.lower() for keyword in code_keywords)
            
            if is_code_query:
                # Use code model directly for faster response
                logger.info("Processing code query...")
                try:
                    code_prompt = f"""Please write a complete Python script for the following request: {command}

                    Requirements:
                    1. Include all necessary imports
                    2. Add error handling
                    3. Include comments explaining the code
                    4. Make the code runnable as a standalone script
                    5. Provide instructions on how to run the code

                    Please format your response as follows:
                    1. First explain what the code does
                    2. Then show the complete code
                    3. Finally provide instructions for running it"""

                    # Direct model call for faster response
                    response = self.models['code'].invoke(code_prompt)
                    code_response = str(response)
                    
                    # Extract code and create a file if needed
                    if '```python' in code_response:
                        code_blocks = re.findall(r'```python\n(.*?)\n```', code_response, re.DOTALL)
                        if code_blocks:
                            script_name = f"generated_script_{int(time.time())}.py"
                            with open(script_name, 'w') as f:
                                f.write(code_blocks[0])
                            return f"{code_response}\n\nI've saved the code to {script_name}. You can run it using 'python {script_name}'"
                    
                    return code_response
                    
                except Exception as e:
                    logger.error(f"Code generation error: {str(e)}")
                    return "There was an error generating the code. Please try rephrasing your request."
            else:
                # Use chat model directly for faster response
                logger.info("Processing query with direct model call...")
                try:
                    # Create a comprehensive prompt
                    enhanced_prompt = f"""Please provide a comprehensive response to: {command}

                    Requirements:
                    1. Break down complex topics into understandable components
                    2. Provide detailed explanations with logical reasoning
                    3. Include relevant examples and analogies
                    4. Consider multiple perspectives
                    5. Suggest related concepts for deeper understanding
                    6. Keep the response clear and engaging
                    
                    If this is a language learning request:
                    1. Start with basic concepts
                    2. Provide practical examples
                    3. Include pronunciation tips if relevant
                    4. Suggest practice exercises
                    5. Make it interactive and engaging"""
                    
                    # Direct model call without the agent chain
                    response = self.models['chat'].invoke(enhanced_prompt)
                    return str(response)
                    
                except Exception as e:
                    logger.error(f"Error in processing: {str(e)}")
                    # Simple fallback
                    return self.models['chat'].invoke(command)
                
        except Exception as e:
            logger.error(f"Error processing command: {str(e)}")
            return "I encountered an error processing that command. Could you try rephrasing it?"

    def run(self):
        try:
            self.speak("Hello! I'm your AI assistant. I can help you with general questions, internet searches, and code-related tasks. How can I help you?")
            
            while True:
                command = self.listen()
                if command:
                    if "exit" in command.lower() or "quit" in command.lower():
                        self.speak("Goodbye!")
                        break
                    response = self.process_command(command)
                    self.speak(response)
                else:
                    print("\nPlease try speaking again.")
                    
        except KeyboardInterrupt:
            print("\nShutting down gracefully...")
        except Exception as e:
            logger.error(f"Runtime error: {str(e)}")
        finally:
            self.cleanup()

    def cleanup(self):
        """Clean up resources"""
        try:
            import shutil
            shutil.rmtree(self.temp_dir)
            interpreter.reset()
            for memory in self.memory.values():
                memory.clear()
            logger.info("Cleanup completed")
        except Exception as e:
            logger.error(f"Cleanup error: {str(e)}")

if __name__ == "__main__":
    try:
        agent = MultiAgent()
        agent.run()
    except Exception as e:
        logger.error(f"Fatal error: {str(e)}")
        sys.exit(1) 