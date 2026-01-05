
import os
import sys
import json
import subprocess
import tempfile
import logging
from typing import Dict, List, Optional
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from pytorch_cnn_service import PyTorchCNNService
    PYTORCH_AVAILABLE = True
except ImportError:
    PYTORCH_AVAILABLE = False
    logger = logging.getLogger(__name__)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class FlutterCNNService:
    
    def __init__(self):
        self.temp_dir = None
        self.use_pytorch = False
        self.pytorch_service = None
        
        if not PYTORCH_AVAILABLE:
            raise RuntimeError("PyTorch is not available. The app requires PyTorch to run the 71% accuracy model.")
        
        pytorch_model = self._find_pytorch_model()
        if not pytorch_model:
            raise FileNotFoundError(
                "Required PyTorch model 'best_repetitions_fluent_logmel_cnn.pt' not found. "
                "This model is required for the app to function. Please ensure the model file exists in python_services/models/"
            )
        
        try:
            self.pytorch_service = PyTorchCNNService(model_path=pytorch_model)
            if not self.pytorch_service or not self.pytorch_service.detector:
                raise RuntimeError("Failed to initialize PyTorch service detector. Model may be corrupted.")
            self.use_pytorch = True
            model_name = os.path.basename(pytorch_model)
            if 'repetitions_fluent' in model_name:
                logger.info("✅ Using PyTorch 2-class model (repetitions vs fluent) - 71% accuracy")
            else:
                logger.warning(f"⚠️ Using PyTorch model: {model_name} (expected repetitions_fluent model)")
        except Exception as e:
            raise RuntimeError(f"Failed to initialize PyTorch CNN service: {e}. The 71% accuracy model is required.")
        
    def _find_pytorch_model(self) -> Optional[str]:

        possible_paths = [
            os.path.join(os.path.dirname(__file__), 'models', 'best_repetitions_fluent_logmel_cnn.pt'),
            os.path.join(os.path.dirname(__file__), 'best_repetitions_fluent_logmel_cnn.pt'),
        ]
        
        for path in possible_paths:
            if os.path.exists(path):
                model_name = os.path.basename(path)
                logger.info(f"✅ Found PyTorch model: {model_name}")
                return path
        
        logger.warning("⚠️ No PyTorch model found: best_repetitions_fluent_logmel_cnn.pt")
        return None
        
    def analyze_audio(self, audio_file_path: str) -> Dict[str, any]:

        if not os.path.exists(audio_file_path):
            return {
                'events': [],
                'summary': {
                    'segmentCount': 0,
                    'hasEvents': False,
                    'error': f'Audio file not found: {audio_file_path}'
                },
                'processing_info': {
                    'error': f'Audio file not found: {audio_file_path}',
                    'model_path': self.pytorch_service.model_path if self.pytorch_service else None,
                    'input_file': audio_file_path
                }
            }
        
        if not self.use_pytorch or not self.pytorch_service:
            return {
                'events': [],
                'summary': {
                    'segmentCount': 0,
                    'hasEvents': False,
                    'error': 'PyTorch model (71% accuracy) not available. This model is required.'
                },
                'processing_info': {
                    'error': 'PyTorch model (71% accuracy) not available. This model is required.',
                    'model_path': None,
                    'input_file': audio_file_path
                }
            }
        
        try:
            logger.info(f"🎯 Starting PyTorch CNN analysis for: {audio_file_path}")
            results = self.pytorch_service.analyze_audio(audio_file_path)
            logger.info(f"✅ PyTorch CNN analysis complete. Found {len(results.get('events', []))} events.")
            return results
        except Exception as e:
            logger.error(f"❌ PyTorch CNN analysis failed: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return {
                'events': [],
                'summary': {
                    'segmentCount': 0,
                    'hasEvents': False,
                    'error': f'PyTorch CNN analysis failed: {e}'
                },
                'processing_info': {
                    'error': f'PyTorch CNN analysis failed: {e}',
                    'model_path': None,
                    'input_file': audio_file_path
                }
            }
    
def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Run CNN analysis for Flutter app')
    parser.add_argument('audio_file', help='Path to audio file')
    parser.add_argument('--output', help='Output JSON file path')
    
    args = parser.parse_args()
    
    service = FlutterCNNService()
    results = service.analyze_audio(args.audio_file)
    
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        logger.info(f"Results saved to: {args.output}")
    
    print(json.dumps(results))

if __name__ == "__main__":
    main()
