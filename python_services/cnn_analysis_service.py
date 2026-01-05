
import os
import sys
import json
import subprocess
import tempfile
import logging
import numpy as np
import traceback
import shutil
from typing import Dict, List, Optional
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from audio_processor import process_audio_file
from precise_stuttering_detector import PreciseStutteringDetector, analyze_audio_with_precise_detection

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class CNNAnalysisService:
    
    def __init__(self, model_path: str = None):
        
        try:
            self.model_path = model_path or self._find_default_model()
            self.temp_dir = None
            
            if self.model_path and not isinstance(self.model_path, str):
                raise ValueError(f"model_path must be a string, got {type(self.model_path)}")
            
        except Exception as e:
            logger.error(f"Failed to initialize CNNAnalysisService: {e}")
            logger.error(traceback.format_exc())
            raise
        
    def _find_default_model(self) -> Optional[str]:
        
        possible_paths = [
            os.path.join(os.path.dirname(__file__), 'models', 'cnn_model.h5'),
            os.path.join(os.path.dirname(__file__), 'cnn_model.h5'),
            os.path.join(os.path.dirname(__file__), '..', 'models', 'cnn_model.h5'),

            os.path.join(os.path.dirname(__file__), 'models', 'cnn_model.tflite'),
            os.path.join(os.path.dirname(__file__), 'cnn_model.tflite'),
            os.path.join(os.path.dirname(__file__), '..', 'models', 'cnn_model.tflite'),
        ]
        
        for path in possible_paths:
            if os.path.exists(path):
                model_type = "H5" if path.endswith('.h5') else "TFLite"
                logger.info(f"Found {model_type} model at: {path}")
                return path
        
        logger.warning("No CNN model found. Please provide model_path.")
        return None
    
    def __enter__(self):
        
        try:
            self.temp_dir = tempfile.mkdtemp()
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
            except (OSError, PermissionError) as e:
                logger.warning(f"Failed to clean up temporary directory {self.temp_dir}: {e}")
            except Exception as e:
                logger.warning(f"Unexpected error cleaning up temp directory: {e}")
    
    def analyze_audio_file(self, audio_file_path: str, output_dir: str = None) -> Dict[str, any]:
        
        if not isinstance(audio_file_path, str) or not audio_file_path:
            raise ValueError(f"Invalid audio_file_path: {audio_file_path}")
        
        if not os.path.exists(audio_file_path):
            raise FileNotFoundError(f"Audio file not found: {audio_file_path}")
        
        if not os.access(audio_file_path, os.R_OK):
            raise PermissionError(f"Cannot read audio file: {audio_file_path}")
        
        if not self.model_path:
            raise ValueError("Model path not set. Cannot perform analysis.")
        
        if not os.path.exists(self.model_path):
            raise FileNotFoundError(f"CNN model not found: {self.model_path}")
        
        if not os.access(self.model_path, os.R_OK):
            raise PermissionError(f"Cannot read model file: {self.model_path}")
        
        logger.info(f"Starting CNN analysis for: {audio_file_path}")
        
        if output_dir is None:
            output_dir = self.temp_dir
        
        try:
            results = process_audio_file(audio_file_path, self.model_path, output_dir)
        except Exception as e:
            logger.error(f"Error processing audio file: {e}")
            logger.error(traceback.format_exc())
            raise
        
        try:
            formatted_results = self._format_results_for_flutter(results)
        except Exception as e:
            logger.error(f"Error formatting results: {e}")
            logger.error(traceback.format_exc())

            return {
                'events': [],
                'summary': {
                    'segmentCount': 0,
                    'hasEvents': False,
                    'error': str(e)
                },
                'processing_info': {
                    'error': str(e),
                    'model_path': self.model_path,
                    'input_file': audio_file_path
                }
            }
        
        logger.info(f"CNN analysis complete. Found {len(formatted_results['events'])} events.")
        return formatted_results
        
    def analyze_audio_file_precise(self, audio_file_path: str, output_dir: str = None) -> Dict[str, any]:
        
        if not isinstance(audio_file_path, str) or not audio_file_path:
            raise ValueError(f"Invalid audio_file_path: {audio_file_path}")
        
        if not os.path.exists(audio_file_path):
            raise FileNotFoundError(f"Audio file not found: {audio_file_path}")
        
        if not os.access(audio_file_path, os.R_OK):
            raise PermissionError(f"Cannot read audio file: {audio_file_path}")
        
        if not self.model_path:
            raise ValueError("Model path not set. Cannot perform analysis.")
        
        if not os.path.exists(self.model_path):
            raise FileNotFoundError(f"CNN model not found: {self.model_path}")
        
        logger.info(f"Starting precise CNN analysis for: {audio_file_path}")
        
        if output_dir is None:
            output_dir = self.temp_dir
        
        try:
            results = process_audio_file(audio_file_path, self.model_path, output_dir)
        except Exception as e:
            logger.error(f"Error processing audio file: {e}")
            logger.error(traceback.format_exc())
            raise
        
        try:
            precise_detector = PreciseStutteringDetector()
        except Exception as e:
            logger.error(f"Failed to initialize PreciseStutteringDetector: {e}")
            raise
        
        precise_events = []
        total_events = 0
        errors = []
        
        for segment in results.get('segments', []):
            try:
                if 'error' in segment:
                    errors.append(f"Segment {segment.get('segment_index', 'unknown')}: {segment.get('error', 'unknown error')}")
                    continue
                
                predictions = segment.get('predictions', {})
                if not predictions:
                    predictions = {'blocks': 0.0, 'prolongations': 0.0, 'repetitions': 0.0, 'fluent': 1.0}
                
                try:
                    segment_analysis = analyze_audio_with_precise_detection(
                        segment.get('audio_path', ''), 
                        predictions
                    )
                except Exception as e:
                    logger.warning(f"Precise detection failed for segment {segment.get('segment_index', 'unknown')}: {e}")
                    errors.append(f"Segment {segment.get('segment_index', 'unknown')}: {str(e)}")
                    continue
                
                for event in segment_analysis.get('events', []):
                    try:

                        segment_start = segment.get('timestamp_start', 0)
                        absolute_start = segment_start + event.get('start_time', 0)
                        absolute_end = segment_start + event.get('end_time', 0)
                        
                        precise_event = {
                            'type': event.get('type', 'unknown'),
                            'confidence': event.get('confidence', 0.0),
                            'probability': int(event.get('confidence', 0.0) * 100),
                            'seconds': int(absolute_start),
                            't0': int(absolute_start * 1000),
                            't1': int(absolute_end * 1000),
                            'duration': event.get('duration', 0),
                            'severity': event.get('severity', 'low'),
                            'source': 'cnn_model_precise',
                            'model_version': 'h5_v1_precise',
                            'segment_start': segment_start,
                            'relative_start': event.get('start_time', 0),
                            'relative_end': event.get('end_time', 0)
                        }
                        
                        precise_events.append(precise_event)
                        total_events += 1
                    except (KeyError, ValueError, TypeError) as e:
                        logger.warning(f"Error formatting event: {e}")
                        continue
                        
            except Exception as e:
                logger.warning(f"Error processing segment: {e}")
                errors.append(str(e))
                continue
        
        try:
            total_segments = results.get('summary', {}).get('total_segments', 0)
            successful_predictions = results.get('summary', {}).get('successful_predictions', 0)
            
            try:
                avg_confidence = np.mean([e['confidence'] for e in precise_events]) if precise_events else 0.0
            except (KeyError, ValueError, TypeError):
                avg_confidence = 0.0
            
            summary = {
                'segmentCount': total_segments,
                'totalSegments': total_segments,
                'successfulPredictions': successful_predictions,
                'preciseEventsDetected': total_events,
                'averageConfidence': float(avg_confidence),
                'dominantType': self._get_dominant_type(precise_events),
                'classDistribution': self._get_class_distribution(precise_events),
                'hasEvents': total_events > 0,
                'processingDetails': {
                    'segmentsAnalyzed': total_segments,
                    'preciseEventsFound': total_events,
                    'segmentDuration': '3.0 seconds',
                    'overlapRatio': '50%',
                    'modelType': 'H5 CNN with Precise Detection'
                }
            }
        except Exception as e:
            logger.error(f"Error creating summary: {e}")
            summary = {
                'segmentCount': 0,
                'totalSegments': 0,
                'successfulPredictions': 0,
                'preciseEventsDetected': total_events,
                'averageConfidence': 0.0,
                'dominantType': 'none',
                'classDistribution': {},
                'hasEvents': total_events > 0,
                'error': str(e)
            }
        
        formatted_results = {
            'events': precise_events,
            'summary': summary,
            'processing_info': {
                'model_path': self.model_path,
                'input_file': audio_file_path,
                'processing_time': 'unknown',
                'errors': errors + results.get('errors', [])
            }
        }
        
        logger.info(f"Precise CNN analysis complete. Found {total_events} precise events.")
        
        return formatted_results
    
    def _get_dominant_type(self, events: List[Dict]) -> str:
        
        if not events:
            return 'none'
        
        type_counts = {}
        for event in events:
            event_type = event['type']
            type_counts[event_type] = type_counts.get(event_type, 0) + 1
        
        return max(type_counts, key=type_counts.get)
    
    def _get_class_distribution(self, events: List[Dict]) -> Dict[str, int]:
        
        distribution = {}
        for event in events:
            event_type = event['type']
            distribution[event_type] = distribution.get(event_type, 0) + 1
        
        return distribution
    
    def _format_results_for_flutter(self, results: Dict[str, any]) -> Dict[str, any]:
        
        events = []
        
        for segment in results.get('segments', []):
            if 'error' in segment:
                continue
            
            predicted_class = segment.get('predicted_class', 'none')
            confidence = segment.get('confidence', 0.0)
            
            if predicted_class == 'none' or confidence < 0.3:
                continue
            
            event = {
                'type': predicted_class,
                'confidence': confidence,
                'probability': int(confidence * 100),
                'seconds': int(segment['timestamp_start']),
                't0': int(segment['timestamp_start'] * 1000),
                't1': int(segment['timestamp_end'] * 1000),
                'source': 'cnn_model',
                'model_version': 'h5_v1'
            }
            
            events.append(event)
        
        total_segments = results['summary'].get('total_segments', 0)
        successful_predictions = results['summary'].get('successful_predictions', 0)
        
        summary = {
            'segmentCount': len(events),
            'totalSegments': total_segments,
            'successfulPredictions': successful_predictions,
            'averageConfidence': results['summary'].get('average_confidence', 0),
            'dominantType': results['summary'].get('dominant_class', 'none'),
            'classDistribution': results['summary'].get('class_distribution', {}),
            'hasEvents': len(events) > 0,
            'processingDetails': {
                'segmentsAnalyzed': successful_predictions,
                'disfluencySegments': len(events),
                'segmentDuration': '5.0 seconds',
                'modelType': 'H5 CNN'
            }
        }
        
        return {
            'events': events,
            'summary': summary,
            'processing_info': {
                'model_path': self.model_path,
                'input_file': results['input_file'],
                'processing_time': 'unknown',
                'errors': results.get('errors', [])
            }
        }
    
    def _calculate_severity(self, confidence: float) -> str:
        
        if confidence >= 0.8:
            return 'high'
        elif confidence >= 0.6:
            return 'medium'
        elif confidence >= 0.4:
            return 'low'
        else:
            return 'very_low'

def run_analysis_from_flutter(audio_file_path: str, model_path: str = None, output_json_path: str = None) -> str:
    
    try:

        if not isinstance(audio_file_path, str) or not audio_file_path:
            raise ValueError(f"Invalid audio_file_path: {audio_file_path}")
        
        with CNNAnalysisService(model_path) as service:
            results = service.analyze_audio_file(audio_file_path)
            
            if output_json_path:
                try:
                    output_dir = os.path.dirname(output_json_path)
                    if output_dir and not os.path.exists(output_dir):
                        os.makedirs(output_dir, exist_ok=True)
                    
                    with open(output_json_path, 'w') as f:
                        json.dump(results, f, indent=2)
                    logger.info(f"Results saved to: {output_json_path}")
                except (OSError, PermissionError, json.JSONEncodeError) as e:
                    logger.error(f"Failed to save results to JSON: {e}")

            return json.dumps(results)
            
    except KeyboardInterrupt:
        logger.warning("Analysis interrupted by user")
        error_result = {
            'events': [],
            'summary': {
                'segmentCount': 0,
                'hasEvents': False,
                'error': 'Analysis interrupted by user'
            },
            'processing_info': {
                'error': 'Analysis interrupted by user',
                'model_path': model_path,
                'input_file': audio_file_path
            }
        }
        return json.dumps(error_result)
    except MemoryError:
        logger.error("Out of memory during analysis")
        error_result = {
            'events': [],
            'summary': {
                'segmentCount': 0,
                'hasEvents': False,
                'error': 'Out of memory error'
            },
            'processing_info': {
                'error': 'Out of memory error',
                'model_path': model_path,
                'input_file': audio_file_path
            }
        }
        return json.dumps(error_result)
    except Exception as e:
        error_result = {
            'events': [],
            'summary': {
                'segmentCount': 0,
                'hasEvents': False,
                'error': str(e)
            },
            'processing_info': {
                'error': str(e),
                'model_path': model_path,
                'input_file': audio_file_path
            }
        }
        
        logger.error(f"CNN analysis failed: {e}")
        logger.error(traceback.format_exc())
        return json.dumps(error_result)

def main():
    
    import argparse
    
    try:
        parser = argparse.ArgumentParser(description='Run CNN analysis on audio file')
        parser.add_argument('audio_file', help='Path to audio file')
        parser.add_argument('--model', help='Path to CNN model')
        parser.add_argument('--output', help='Output JSON file path')
        
        args = parser.parse_args()
        
        result_json = run_analysis_from_flutter(args.audio_file, args.model, args.output)
        
        print(result_json)
        
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
