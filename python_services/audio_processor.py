
import os
import sys
import json
import librosa
import numpy as np
import matplotlib.pyplot as plt
from pydub import AudioSegment
from scipy.ndimage import zoom
import tempfile
import argparse
from typing import List, Dict, Tuple, Optional
import logging
import traceback
import shutil

import tensorflow as tf
from tensorflow.keras.models import load_model
from tensorflow.keras.utils import load_img, img_to_array

try:
    import tflite_runtime.interpreter as tflite
    TFLITE_AVAILABLE = True
except ImportError:
    try:
        import tensorflow.lite as tflite
        TFLITE_AVAILABLE = True
    except ImportError:
        TFLITE_AVAILABLE = False
        print("Warning: TensorFlow Lite not available, falling back to Keras")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class AudioProcessor:
    
    def __init__(self, segment_duration: float = 3.0, target_size: Tuple[int, int] = (128, 128), 
                 overlap_ratio: float = 0.5, min_segment_duration: float = 1.0):
        
        try:

            if segment_duration <= 0:
                raise ValueError(f"segment_duration must be positive, got {segment_duration}")
            if not isinstance(target_size, tuple) or len(target_size) != 2:
                raise ValueError(f"target_size must be a tuple of 2 integers, got {target_size}")
            if any(not isinstance(x, int) or x <= 0 for x in target_size):
                raise ValueError(f"target_size values must be positive integers, got {target_size}")
            if not 0 <= overlap_ratio < 1:
                raise ValueError(f"overlap_ratio must be in [0, 1), got {overlap_ratio}")
            if min_segment_duration <= 0:
                raise ValueError(f"min_segment_duration must be positive, got {min_segment_duration}")
            if min_segment_duration > segment_duration:
                raise ValueError(f"min_segment_duration ({min_segment_duration}) cannot exceed segment_duration ({segment_duration})")
            
            self.segment_duration = segment_duration
            self.target_size = target_size
            self.overlap_ratio = overlap_ratio
            self.min_segment_duration = min_segment_duration
            self.temp_dir = None
            
        except ValueError as e:
            logger.error(f"Invalid AudioProcessor parameters: {e}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error initializing AudioProcessor: {e}")
            logger.error(traceback.format_exc())
            raise
        
    def __enter__(self):
        
        try:
            self.temp_dir = tempfile.mkdtemp()
            logger.info(f"Created temporary directory: {self.temp_dir}")
            return self
        except (OSError, PermissionError) as e:
            logger.error(f"Failed to create temporary directory: {e}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error creating temp directory: {e}")
            raise
        
    def __exit__(self, exc_type, exc_val, exc_tb):
        
        if self.temp_dir and os.path.exists(self.temp_dir):
            try:
                shutil.rmtree(self.temp_dir)
                logger.info(f"Cleaned up temporary directory: {self.temp_dir}")
            except (OSError, PermissionError) as e:
                logger.warning(f"Failed to clean up temporary directory {self.temp_dir}: {e}")
            except Exception as e:
                logger.warning(f"Unexpected error cleaning up temp directory: {e}")
    
    def extend_audio_to_duration(self, input_file: str, output_file: str, duration_ms: int) -> None:
        
        if not isinstance(input_file, str) or not input_file:
            raise ValueError(f"Invalid input_file: {input_file}")
        if not isinstance(output_file, str) or not output_file:
            raise ValueError(f"Invalid output_file: {output_file}")
        if not isinstance(duration_ms, int) or duration_ms <= 0:
            raise ValueError(f"duration_ms must be a positive integer, got {duration_ms}")
        
        if not os.path.exists(input_file):
            raise FileNotFoundError(f"Input file not found: {input_file}")
        
        if not os.access(input_file, os.R_OK):
            raise PermissionError(f"Cannot read input file: {input_file}")
        
        try:
            audio = AudioSegment.from_file(input_file)
        except Exception as e:
            logger.error(f"Failed to load audio file {input_file}: {e}")
            raise
        
        if len(audio) > duration_ms:
            num_segments = (len(audio) + duration_ms - 1) // duration_ms
            
            for i in range(num_segments):

                start_ms = i * duration_ms
                end_ms = min((i + 1) * duration_ms, len(audio))
                segment = audio[start_ms:end_ms]
                
                if len(segment) < duration_ms:
                    silence_needed = duration_ms - len(segment)
                    silence = AudioSegment.silent(duration=silence_needed)
                    segment = segment + silence
                
                if i == 0:
                    segment_output = output_file
                else:
                    base_name = os.path.splitext(output_file)[0]
                    ext = os.path.splitext(output_file)[1]
                    segment_output = f"{base_name}_segment_{i+1}{ext}"
                
                try:

                    output_dir = os.path.dirname(segment_output)
                    if output_dir and not os.path.exists(output_dir):
                        os.makedirs(output_dir, exist_ok=True)
                    
                    segment.export(segment_output, format="wav")
                    logger.info(f"Audio segment saved as '{segment_output}' with length {len(segment) / 1000:.2f} seconds.")
                except (OSError, PermissionError) as e:
                    logger.error(f"Failed to export segment to {segment_output}: {e}")
                    raise
                except Exception as e:
                    logger.error(f"Unexpected error exporting segment: {e}")
                    raise
        else:

            total_silence_needed = max(duration_ms - len(audio), 0)
            
            try:
                silence_start = AudioSegment.silent(duration=total_silence_needed // 2)
                silence_end = AudioSegment.silent(duration=total_silence_needed - (total_silence_needed // 2))
                
                extended_audio = silence_start + audio + silence_end
            except Exception as e:
                logger.error(f"Failed to create extended audio: {e}")
                raise
            
            try:

                output_dir = os.path.dirname(output_file)
                if output_dir and not os.path.exists(output_dir):
                    os.makedirs(output_dir, exist_ok=True)
                
                extended_audio.export(output_file, format="wav")
                logger.info(f"Audio saved as '{output_file}' with length {len(extended_audio) / 1000:.2f} seconds.")
            except (OSError, PermissionError) as e:
                logger.error(f"Failed to export audio to {output_file}: {e}")
                raise
            except Exception as e:
                logger.error(f"Unexpected error exporting audio: {e}")
                raise
    
    def resize_spectrogram(self, spectrogram: np.ndarray, target_size: Tuple[int, int]) -> np.ndarray:
        
        if not isinstance(spectrogram, np.ndarray):
            raise ValueError(f"spectrogram must be a numpy array, got {type(spectrogram)}")
        if spectrogram.size == 0:
            raise ValueError("spectrogram cannot be empty")
        if len(spectrogram.shape) != 2:
            raise ValueError(f"spectrogram must be 2D, got shape {spectrogram.shape}")
        
        try:
            current_height, current_width = spectrogram.shape
            
            if current_height <= 0 or current_width <= 0:
                raise ValueError(f"Invalid spectrogram dimensions: {current_height}x{current_width}")
            
            height_scale = target_size[0] / current_height
            width_scale = target_size[1] / current_width
            
            if height_scale <= 0 or width_scale <= 0:
                raise ValueError(f"Invalid scaling factors: height={height_scale}, width={width_scale}")
            
            resized_spectrogram = zoom(spectrogram, (height_scale, width_scale), order=1)
            
            return resized_spectrogram[:target_size[0], :target_size[1]]
            
        except (ValueError, ZeroDivisionError) as e:
            logger.error(f"Error resizing spectrogram: {e}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error resizing spectrogram: {e}")
            logger.error(traceback.format_exc())
            raise
    
    def generate_mel_spectrogram(self, audio_path: str, target_size: Tuple[int, int] = None) -> np.ndarray:
        
        if not isinstance(audio_path, str) or not audio_path:
            raise ValueError(f"Invalid audio_path: {audio_path}")
        
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"Audio file not found: {audio_path}")
        
        if target_size is None:
            target_size = self.target_size
        
        try:
            y, sr = librosa.load(audio_path, sr=22050, duration=self.segment_duration)
        except Exception as e:

            error_str = str(e).lower()
            if 'backend' in error_str or 'no decoder' in error_str or 'could not find' in error_str:
                logger.error(f"No audio backend available for {audio_path}: {e}")
            else:
                logger.error(f"Error loading audio file {audio_path}: {e}")
            raise
        
        if y is None or len(y) == 0:
            raise ValueError(f"Empty or invalid audio data in {audio_path}")
        
        if sr is None or sr <= 0:
            raise ValueError(f"Invalid sample rate ({sr}) for {audio_path}")
        
        try:
            y = librosa.effects.preemphasis(y)
        except Exception as e:
            logger.warning(f"Error applying pre-emphasis filter: {e}, continuing without it")

        try:
            mel_spectrogram = librosa.feature.melspectrogram(
                y=y, 
                sr=sr,
                n_mels=128,
                n_fft=2048,
                hop_length=512,
                fmin=50,
                fmax=sr//2,
                window='hann'
            )
        except Exception as e:
            logger.error(f"Error generating mel spectrogram from {audio_path}: {e}")
            raise
        
        if mel_spectrogram is None or mel_spectrogram.size == 0:
            raise ValueError(f"Invalid spectrogram generated for {audio_path}")
        
        try:
            mel_spectrogram_db = librosa.power_to_db(mel_spectrogram, ref=np.max, top_db=80)
        except Exception as e:
            logger.error(f"Error converting to dB scale: {e}")
            raise
        
        try:
            resized_spectrogram = self.resize_spectrogram(mel_spectrogram_db, target_size)
        except Exception as e:
            logger.error(f"Error resizing spectrogram: {e}")
            raise
        
        return resized_spectrogram
    
    def save_spectrogram_as_image(self, spectrogram: np.ndarray, output_path: str) -> None:
        
        if not isinstance(spectrogram, np.ndarray) or spectrogram.size == 0:
            raise ValueError("spectrogram must be a non-empty numpy array")
        if not isinstance(output_path, str) or not output_path:
            raise ValueError(f"Invalid output_path: {output_path}")
        
        fig = None
        try:

            output_dir = os.path.dirname(output_path)
            if output_dir and not os.path.exists(output_dir):
                try:
                    os.makedirs(output_dir, exist_ok=True)
                except (OSError, PermissionError) as e:
                    logger.error(f"Cannot create output directory {output_dir}: {e}")
                    raise
            
            if output_dir and not os.access(output_dir, os.W_OK):
                raise PermissionError(f"Cannot write to directory: {output_dir}")
            
            fig = plt.figure(figsize=(8, 8))
            librosa.display.specshow(spectrogram)
            plt.axis('off')
            plt.tight_layout()
            
            try:
                plt.savefig(output_path, bbox_inches='tight', pad_inches=0, dpi=100)
                logger.info(f"Spectrogram saved as image: {output_path}")
            except (IOError, OSError, PermissionError) as e:
                logger.error(f"Failed to save image to {output_path}: {e}")
                raise
            finally:
                if fig is not None:
                    plt.close(fig)
                    fig = None
                    
        except Exception as e:
            if fig is not None:
                plt.close(fig)
            logger.error(f"Error saving spectrogram image: {e}")
            raise
    
    def segment_audio_file(self, input_file: str) -> List[str]:
        
        if not isinstance(input_file, str) or not input_file:
            raise ValueError(f"Invalid input_file: {input_file}")
        
        if not os.path.exists(input_file):
            raise FileNotFoundError(f"Input file not found: {input_file}")
        
        if not os.access(input_file, os.R_OK):
            raise PermissionError(f"Cannot read input file: {input_file}")
        
        if self.temp_dir is None:
            raise RuntimeError("temp_dir not initialized. Use AudioProcessor as context manager.")
        
        logger.info(f"Processing audio file: {input_file}")
        
        try:
            audio = AudioSegment.from_file(input_file)
        except Exception as e:
            logger.error(f"Failed to load audio file {input_file}: {e}")
            raise
        
        if len(audio) == 0:
            raise ValueError(f"Audio file is empty: {input_file}")
        
        duration_ms = len(audio)
        segment_duration_ms = int(self.segment_duration * 1000)
        min_segment_duration_ms = int(self.min_segment_duration * 1000)
        
        logger.info(f"Audio duration: {duration_ms / 1000:.2f} seconds")
        
        spectrogram_paths = []
        
        step_size_ms = int(segment_duration_ms * (1 - self.overlap_ratio))
        
        if duration_ms <= segment_duration_ms:

            if duration_ms < min_segment_duration_ms:
                logger.info("Audio too short, padding to minimum duration")
                silence_needed = min_segment_duration_ms - duration_ms
                silence = AudioSegment.silent(duration=silence_needed)
                audio = audio + silence
                duration_ms = len(audio)
            
            num_segments = 1
        else:

            num_segments = max(1, int((duration_ms - segment_duration_ms) / step_size_ms) + 1)
        
        logger.info(f"Creating {num_segments} overlapping segments of {self.segment_duration} seconds each")
        logger.info(f"Overlap ratio: {self.overlap_ratio:.1%}, Step size: {step_size_ms}ms")
        
        for i in range(num_segments):
            try:

                start_ms = i * step_size_ms
                end_ms = min(start_ms + segment_duration_ms, duration_ms)
                segment = audio[start_ms:end_ms]
                
                if len(segment) < min_segment_duration_ms:
                    logger.info(f"Segment {i+1} too short ({len(segment)}ms), padding to minimum duration")
                    silence_needed = min_segment_duration_ms - len(segment)
                    silence = AudioSegment.silent(duration=silence_needed)
                    segment = segment + silence
                elif len(segment) < segment_duration_ms:

                    if len(segment) >= segment_duration_ms * 0.8:
                        silence_needed = segment_duration_ms - len(segment)
                        silence = AudioSegment.silent(duration=silence_needed)
                        segment = segment + silence
                
                segment_path = os.path.join(self.temp_dir, f"segment_{i+1}.wav")
                try:
                    segment.export(segment_path, format="wav")
                except Exception as e:
                    logger.error(f"Failed to export segment {i+1} to {segment_path}: {e}")
                    continue
                
                try:
                    spectrogram = self.generate_mel_spectrogram(segment_path)
                except Exception as e:
                    logger.error(f"Failed to generate spectrogram for segment {i+1}: {e}")
                    continue
                
                spectrogram_path = os.path.join(self.temp_dir, f"spectrogram_{i+1}.png")
                try:
                    self.save_spectrogram_as_image(spectrogram, spectrogram_path)
                except Exception as e:
                    logger.error(f"Failed to save spectrogram image for segment {i+1}: {e}")
                    continue
                
                spectrogram_paths.append(spectrogram_path)
                
                logger.info(f"Created segment {i+1}/{num_segments}: {spectrogram_path} "
                           f"(start: {start_ms}ms, duration: {len(segment)}ms)")
            
            except KeyboardInterrupt:
                logger.warning("Processing interrupted by user")
                raise
            except MemoryError:
                logger.error(f"Out of memory processing segment {i+1}")
                raise
            except Exception as e:
                logger.error(f"Unexpected error processing segment {i+1}: {e}")
                logger.debug(traceback.format_exc())
                continue
        
        if not spectrogram_paths:
            raise RuntimeError("No spectrograms were successfully generated")
        
        return spectrogram_paths

class CNNModelPredictor:
    
    def __init__(self, model_path: str, class_names: List[str] = None):
        
        self.model_path = model_path
        self.class_names = class_names or self._load_class_names()
        self.model = None
        self.interpreter = None
        self.input_details = None
        self.output_details = None
        self.use_tflite = False
    
    def _load_class_names(self) -> List[str]:
        
        try:
            class_names_path = os.path.join(os.path.dirname(self.model_path), 'class_names.txt')
            if os.path.exists(class_names_path):
                with open(class_names_path, 'r') as f:
                    return [line.strip() for line in f.readlines() if line.strip()]
            else:
                logger.warning(f"Class names file not found at {class_names_path}, using defaults")
                return ['blocks', 'prolongations', 'repetitions']
        except Exception as e:
            logger.warning(f"Error loading class names: {e}, using defaults")
            return ['blocks', 'prolongations', 'repetitions']
        
    def load_model(self) -> None:
        
        if not isinstance(self.model_path, str) or not self.model_path:
            raise ValueError(f"Invalid model_path: {self.model_path}")
        
        if not os.path.exists(self.model_path):
            raise FileNotFoundError(f"Model file not found: {self.model_path}")
        
        if not os.access(self.model_path, os.R_OK):
            raise PermissionError(f"Cannot read model file: {self.model_path}")
        
        if self.model_path.endswith('.tflite') and TFLITE_AVAILABLE:
            try:
                logger.info(f"Loading optimized TensorFlow Lite model from: {self.model_path}")
                self.interpreter = tflite.Interpreter(model_path=self.model_path)
                self.interpreter.allocate_tensors()
                
                self.input_details = self.interpreter.get_input_details()
                self.output_details = self.interpreter.get_output_details()
                
                self.use_tflite = True
                logger.info("Optimized TensorFlow Lite model loaded successfully")
            except Exception as e:
                logger.error(f"Failed to load TFLite model: {e}")
                logger.error(traceback.format_exc())
                raise
            
        elif self.model_path.endswith('.keras'):
            try:
                logger.info(f"Loading Keras model from: {self.model_path}")
                self.model = load_model(self.model_path)
                self.use_tflite = False
                logger.info("Keras model loaded successfully")
            except Exception as e:
                logger.error(f"Failed to load Keras model: {e}")
                logger.error(traceback.format_exc())
                raise
            
        elif self.model_path.endswith('.h5'):
            try:
                logger.info(f"Loading Keras H5 model from: {self.model_path}")
                self.model = load_model(self.model_path)
                self.use_tflite = False
                logger.info("Keras H5 model loaded successfully")
            except Exception as e:
                logger.error(f"Failed to load H5 model: {e}")
                logger.error(traceback.format_exc())
                raise
            
        else:

            try:
                logger.info(f"Loading Keras model from: {self.model_path}")
                if not TFLITE_AVAILABLE:
                    logger.warning("TensorFlow Lite not available, using Keras model")
                self.model = load_model(self.model_path)
                self.use_tflite = False
                logger.info("Keras model loaded successfully")
            except Exception as e:
                logger.error(f"Failed to load model: {e}")
                logger.error(traceback.format_exc())
                raise
    
    def predict_image(self, image_path: str) -> Dict[str, float]:
        
        if self.use_tflite:
            if self.interpreter is None:
                raise RuntimeError("TFLite model not loaded. Call load_model() first.")
        else:
            if self.model is None:
                raise RuntimeError("Keras model not loaded. Call load_model() first.")
        
        if not isinstance(image_path, str) or not image_path:
            raise ValueError(f"Invalid image_path: {image_path}")
        
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"Image file not found: {image_path}")
        
        if not os.access(image_path, os.R_OK):
            raise PermissionError(f"Cannot read image file: {image_path}")
        
        try:
            if self.use_tflite:

                img = load_img(image_path, target_size=(128, 128))
                img_array = img_to_array(img)
                img_array = img_array.astype(np.float32) / 255.0
                img_array = np.expand_dims(img_array, axis=0)
            else:

                img = load_img(image_path, target_size=(128, 128))
                img_array = img_to_array(img)
                img_array = img_array / 255.0
                img_array = np.expand_dims(img_array, axis=0)
        except Exception as e:
            logger.error(f"Failed to load/preprocess image {image_path}: {e}")
            raise
        
        if img_array is None or img_array.size == 0:
            raise ValueError(f"Invalid preprocessed image from {image_path}")
        
        try:
            if self.use_tflite:

                self.interpreter.set_tensor(self.input_details[0]['index'], img_array)
                
                self.interpreter.invoke()
                
                predictions = self.interpreter.get_tensor(self.output_details[0]['index'])
            else:

                predictions = self.model.predict(img_array, verbose=0)
        except Exception as e:
            logger.error(f"Prediction failed for {image_path}: {e}")
            logger.error(traceback.format_exc())
            raise
        
        if predictions is None or len(predictions) == 0 or len(predictions[0]) == 0:
            raise ValueError(f"Invalid predictions from model for {image_path}")
        
        if len(predictions[0]) != len(self.class_names):
            logger.warning(f"Prediction length ({len(predictions[0])}) doesn't match class names ({len(self.class_names)})")
        
        try:
            result = {}
            for i, class_name in enumerate(self.class_names):
                if i < len(predictions[0]):
                    result[class_name] = float(predictions[0][i])
                else:
                    result[class_name] = 0.0
        except (IndexError, ValueError) as e:
            logger.error(f"Error converting predictions to dictionary: {e}")
            raise
        
        return result
    
    def predict_spectrograms(self, spectrogram_paths: List[str]) -> List[Dict[str, any]]:
        
        results = []
        
        for i, path in enumerate(spectrogram_paths):
            try:
                predictions = self.predict_image(path)
                
                predicted_class = max(predictions, key=predictions.get)
                confidence = predictions[predicted_class]
                
                result = {
                    'segment_index': i + 1,
                    'image_path': path,
                    'predictions': predictions,
                    'predicted_class': predicted_class,
                    'confidence': confidence,
                    'timestamp_start': i * 5.0,
                    'timestamp_end': (i + 1) * 5.0
                }
                
                results.append(result)
                logger.info(f"Segment {i+1}: {predicted_class} (confidence: {confidence:.3f})")
                
            except Exception as e:
                logger.error(f"Error predicting segment {i+1}: {e}")
                results.append({
                    'segment_index': i + 1,
                    'image_path': path,
                    'error': str(e),
                    'timestamp_start': i * 5.0,
                    'timestamp_end': (i + 1) * 5.0
                })
        
        return results

def process_audio_file(input_file: str, model_path: str, output_dir: str = None) -> Dict[str, any]:
    
    if not isinstance(input_file, str) or not input_file:
        raise ValueError(f"Invalid input_file: {input_file}")
    if not isinstance(model_path, str) or not model_path:
        raise ValueError(f"Invalid model_path: {model_path}")
    
    if output_dir is None:
        output_dir = os.path.dirname(input_file) if input_file else os.getcwd()
    
    try:
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
    except (OSError, PermissionError) as e:
        logger.error(f"Cannot create output directory {output_dir}: {e}")
        raise
    
    results = {
        'input_file': input_file,
        'model_path': model_path,
        'output_dir': output_dir,
        'segments': [],
        'summary': {},
        'errors': []
    }
    
    try:

        with AudioProcessor() as processor:

            try:
                spectrogram_paths = processor.segment_audio_file(input_file)
            except Exception as e:
                logger.error(f"Failed to segment audio file: {e}")
                results['errors'].append(f"Segmentation error: {str(e)}")
                return results
            
            if not spectrogram_paths:
                logger.warning("No spectrograms were generated")
                results['errors'].append("No spectrograms generated")
                results['summary'] = {
                    'total_segments': 0,
                    'successful_predictions': 0,
                    'class_distribution': {},
                    'average_confidence': 0,
                    'dominant_class': None
                }
                return results
            
            try:
                predictor = CNNModelPredictor(model_path)
                predictor.load_model()
            except Exception as e:
                logger.error(f"Failed to load model: {e}")
                results['errors'].append(f"Model loading error: {str(e)}")
                return results
            
            try:
                predictions = predictor.predict_spectrograms(spectrogram_paths)
            except Exception as e:
                logger.error(f"Failed to get predictions: {e}")
                results['errors'].append(f"Prediction error: {str(e)}")
                return results
            
            results['segments'] = predictions
            
            successful_predictions = [p for p in predictions if 'error' not in p]
            if successful_predictions:
                try:
                    class_counts = {}
                    total_confidence = 0
                    
                    for pred in successful_predictions:
                        class_name = pred.get('predicted_class', 'unknown')
                        confidence = pred.get('confidence', 0.0)
                        class_counts[class_name] = class_counts.get(class_name, 0) + 1
                        total_confidence += confidence
                    
                    results['summary'] = {
                        'total_segments': len(predictions),
                        'successful_predictions': len(successful_predictions),
                        'class_distribution': class_counts,
                        'average_confidence': total_confidence / len(successful_predictions) if successful_predictions else 0,
                        'dominant_class': max(class_counts, key=class_counts.get) if class_counts else None
                    }
                except Exception as e:
                    logger.error(f"Error calculating summary statistics: {e}")
                    results['errors'].append(f"Summary calculation error: {str(e)}")
            else:
                results['summary'] = {
                    'total_segments': len(predictions),
                    'successful_predictions': 0,
                    'class_distribution': {},
                    'average_confidence': 0,
                    'dominant_class': None
                }
            
            logger.info(f"Processing complete. {len(successful_predictions)}/{len(predictions)} segments processed successfully")
            
    except KeyboardInterrupt:
        logger.warning("Processing interrupted by user")
        results['errors'].append("Processing interrupted by user")
        raise
    except MemoryError:
        logger.error("Out of memory during processing")
        results['errors'].append("Out of memory error")
        raise
    except Exception as e:
        logger.error(f"Error processing audio file: {e}")
        logger.error(traceback.format_exc())
        results['errors'].append(str(e))
    
    return results

def main():
    
    try:
        parser = argparse.ArgumentParser(description='Process audio file for CNN analysis')
        parser.add_argument('input_file', help='Path to input audio file')
        parser.add_argument('model_path', help='Path to trained CNN model')
        parser.add_argument('--output-dir', help='Output directory for results')
        parser.add_argument('--output-json', help='Path to save results as JSON')
        
        args = parser.parse_args()
        
        results = process_audio_file(args.input_file, args.model_path, args.output_dir)
        
        if args.output_json:
            try:
                output_dir = os.path.dirname(args.output_json)
                if output_dir and not os.path.exists(output_dir):
                    os.makedirs(output_dir, exist_ok=True)
                
                with open(args.output_json, 'w') as f:
                    json.dump(results, f, indent=2)
                logger.info(f"Results saved to: {args.output_json}")
            except (OSError, PermissionError, json.JSONEncodeError) as e:
                logger.error(f"Failed to save results to JSON: {e}")
        
        print(f"\nProcessing Summary:")
        print(f"Input file: {results['input_file']}")
        print(f"Total segments: {results['summary'].get('total_segments', 0)}")
        print(f"Successful predictions: {results['summary'].get('successful_predictions', 0)}")
        
        if 'class_distribution' in results['summary']:
            print(f"Class distribution: {results['summary']['class_distribution']}")
            print(f"Dominant class: {results['summary'].get('dominant_class', 'None')}")
            print(f"Average confidence: {results['summary'].get('average_confidence', 0):.3f}")
        
        if results['errors']:
            print(f"Errors: {results['errors']}")
        
        return 0
        
    except KeyboardInterrupt:
        logger.warning("\nProcess interrupted by user")
        return 130
    except Exception as e:
        logger.error(f"Fatal error in main: {e}")
        logger.error(traceback.format_exc())
        return 1

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
