import speech_recognition as sr
import pyttsx3
import requests
import json
import os
import subprocess
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import re
from langchain.prompts import PromptTemplate
from langchain.chains import LLMChain
from langchain.llms import Ollama

class ModelRouter:
    def __init__(self, models: Dict[str, Ollama]):
        self.models = models
        self.task_patterns = {
            'code': r'(code|program|script|function|class|bug|error|debug|implement|develop)',
            'chat': r'(chat|talk|speak|converse|discuss|explain|help|assist)',
            'creative': r'(story|poem|creative|imagine|generate|write|compose)',
            'analysis': r'(analyze|examine|investigate|research|study|evaluate)',
        }
        
    def choose_model(self, query: str) -> Tuple[str, Ollama]:
        # Convert query to lowercase for pattern matching
        query = query.lower()
        
        # Score each model type based on pattern matches
        scores = {
            'code': len(re.findall(self.task_patterns['code'], query)),
            'chat': len(re.findall(self.task_patterns['chat'], query)),
            'creative': len(re.findall(self.task_patterns['creative'], query)),
            'analysis': len(re.findall(self.task_patterns['analysis'], query)),
        }
        
        # Default to chat model if no clear pattern is found
        if max(scores.values()) == 0:
            return 'chat', self.models['chat']
            
        # Get the model type with highest score
        model_type = max(scores.items(), key=lambda x: x[1])[0]
        
        # Map model types to specific models
        model_mapping = {
            'code': 'code',
            'chat': 'chat',
            'creative': 'chat',
            'analysis': 'chat'
        }
        
        chosen_type = model_mapping[model_type]
        return model_type, self.models[chosen_type]

class MultiAgentAssistant:
    def __init__(self):
        # Check model availability first
        self.available_models = self._check_available_models()
        
        # Initialize models based on availability
        self.models = {}
        if 'mistral:7b-instruct-q4_K_M' in self.available_models:
            self.models['chat'] = Ollama(model="mistral:7b-instruct-q4_K_M")
        elif 'neural-chat:7b-v3.3-q4_K_M' in self.available_models:
            self.models['chat'] = Ollama(model="neural-chat:7b-v3.3-q4_K_M")
        elif 'llama2:7b-chat-q4_K_M' in self.available_models:
            self.models['chat'] = Ollama(model="llama2:7b-chat-q4_K_M")
        else:
            raise RuntimeError("No suitable chat model available")
            
        if 'codellama:7b-instruct-q4_K_M' in self.available_models:
            self.models['code'] = Ollama(model="codellama:7b-instruct-q4_K_M")
        else:
            print("Warning: Code-specific model not available, using chat model for code tasks")
            self.models['code'] = self.models['chat']
        
        # Initialize model router
        self.router = ModelRouter(self.models)
        
        # Initialize chains with appropriate prompts
        self.chains = {
            'chat': LLMChain(
                llm=self.models['chat'],
                prompt=PromptTemplate(
                    template="You are a helpful AI assistant. {query}",
                    input_variables=["query"]
                )
            ),
            'code': LLMChain(
                llm=self.models['code'],
                prompt=PromptTemplate(
                    template="You are an expert programmer. {query}",
                    input_variables=["query"]
                )
            )
        }
    
    def _check_available_models(self) -> List[str]:
        """Check which models are available on the Ollama server."""
        try:
            response = requests.get("http://localhost:11434/api/tags")
            if response.status_code == 200:
                models = [model['name'] for model in response.json()['models']]
                print(f"Available models: {', '.join(models)}")
                return models
            else:
                print(f"Warning: Failed to get model list (status {response.status_code})")
                return []
        except Exception as e:
            print(f"Warning: Failed to check available models: {str(e)}")
            return []
    
    async def process_query(self, query: str, language: str = 'en') -> str:
        # Choose appropriate model based on query
        task_type, model = self.router.choose_model(query)
        
        # Get appropriate chain
        chain = self.chains.get(task_type, self.chains['chat'])
        
        try:
            # Process query
            response = await chain.arun(query=query)
            return response
        except Exception as e:
            print(f"Error processing query with {task_type} model: {str(e)}")
            # Try fallback to chat model if different model failed
            if task_type != 'chat':
                print("Falling back to chat model")
                return await self.chains['chat'].arun(query=query)
            raise

class MultiAgent:
    def __init__(self):
        self.recognizer = sr.Recognizer()
        self.engine = pyttsx3.init()
        self.ollama_url = "http://localhost:11434/api/generate"
        
    def listen(self):
        with sr.Microphone() as source:
            print("Listening...")
            audio = self.recognizer.listen(source)
            try:
                text = self.recognizer.recognize_google(audio)
                print(f"You said: {text}")
                return text
            except Exception as e:
                print(f"Error: {str(e)}")
                return None

    def speak(self, text):
        print(f"AI: {text}")
        self.engine.say(text)
        self.engine.runAndWait()

    def process_command(self, command):
        data = {
            "model": "codellama",
            "prompt": command,
            "stream": False
        }
        response = requests.post(self.ollama_url, json=data)
        if response.status_code == 200:
            return response.json()['response']
        return "Sorry, I couldn't process that command."

    def run(self):
        self.speak("Hello! I'm your AI assistant. How can I help you?")
        while True:
            command = self.listen()
            if command:
                if "exit" in command.lower():
                    self.speak("Goodbye!")
                    break
                response = self.process_command(command)
                self.speak(response)

if __name__ == "__main__":
    agent = MultiAgent()
    agent.run()
