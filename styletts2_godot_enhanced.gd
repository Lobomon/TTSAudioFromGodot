# StyleTTS2FileClientEnhanced.gd
# Enhanced version with voice cloning support
# Attach this script to a Node in your Godot scene

extends Node
class_name StyleTTS2Enhanced

# File paths (pointing to C:\tmp)
const BASE_PATH = "C:/tmp/"
const REQUEST_FILE = BASE_PATH + "tts_request.json"
const STATUS_FILE = BASE_PATH + "tts_status.json"
const DEFAULT_OUTPUT = BASE_PATH + "MyOutput.wav"

# Status tracking
var current_request_id: String = ""
var is_waiting_for_audio: bool = false
var last_status: Dictionary = {}
var current_output_file: String = DEFAULT_OUTPUT

# Available voices (loaded from Python)
var available_voices: Array = []

# Signals
signal audio_ready_to_read(message: String, filename: String)
signal audio_ready(audio_file: String, duration: float)
signal audio_error(error_message: String)
signal status_changed(status: String, message: String, progress: int)

func _ready():
	# Check if base directory exists
	if not DirAccess.dir_exists_absolute(BASE_PATH):
		print("Warning: Directory ", BASE_PATH, " does not exist!")
		print("Please make sure the Python script is running and the directory exists.")
	
	# Start monitoring status file
	set_process(true)
	print("StyleTTS2 Enhanced Godot Client initialized")
	print("Base path: ", BASE_PATH)
	print("Request file: ", REQUEST_FILE)
	print("Status file: ", STATUS_FILE)

func _process(_delta):
	if is_waiting_for_audio:
		check_status()

# Add function to get available voices
func get_available_voices() -> Array:
	"""Get list of available voices"""
	return available_voices

func set_available_voices(voices: Array):
	"""Set the available voices (can be called after getting them from Python)"""
	available_voices = voices
	print("Available voices updated: ", voices)

# ENHANCED: Predefined voice generation (original functionality)
func generate_speech(text: String, voice: String = "m-us-2", speed: int = 120, 
					diffusion_steps: int = 7, alpha: float = 0.3, beta: float = 0.7, 
					embedding_scale: float = 1.0, filename: String = "") -> bool:
	"""
	Generate speech using predefined voices
	"""
	var request_data = {
		"type": "predefined",
		"text": text,
		"voice": voice,
		"speed": speed,
		"diffusion_steps": diffusion_steps,
		"alpha": alpha,
		"beta": beta,
		"embedding_scale": embedding_scale
	}
	
	if filename != "":
		request_data["filename"] = filename
		current_output_file = BASE_PATH + filename
	else:
		current_output_file = DEFAULT_OUTPUT
	
	return await _send_request(request_data)

# NEW: Voice cloning generation
func generate_speech_clone(text: String, voice_file_path: String, speed: int = 120,
						  diffusion_steps: int = 20, alpha: float = 0.3, beta: float = 0.7,
						  embedding_scale: float = 1.0, filename: String = "") -> bool:
	"""
	Generate speech using voice cloning from a voice file
	voice_file_path: Path to the voice sample file (e.g., "C:/tmp/uploads/my_voice.wav")
	"""
	if not FileAccess.file_exists(voice_file_path):
		push_error("Voice file not found: " + voice_file_path)
		return false
	
	var request_data = {
		"type": "clone",
		"text": text,
		"voice_file_path": voice_file_path,
		"speed": speed,
		"diffusion_steps": diffusion_steps,
		"alpha": alpha,
		"beta": beta,
		"embedding_scale": embedding_scale
	}
	
	if filename != "":
		request_data["filename"] = filename
		current_output_file = BASE_PATH + filename
	else:
		current_output_file = DEFAULT_OUTPUT
	
	print("Requesting voice cloning with file: ", voice_file_path)
	return await _send_request(request_data)

# NEW: LJSpeech generation
func generate_speech_ljspeech(text: String, diffusion_steps: int = 7, 
							 embedding_scale: float = 1.0, filename: String = "") -> bool:
	"""
	Generate speech using the LJSpeech model
	"""
	var request_data = {
		"type": "ljspeech",
		"text": text,
		"diffusion_steps": diffusion_steps,
		"embedding_scale": embedding_scale
	}
	
	if filename != "":
		request_data["filename"] = filename
		current_output_file = BASE_PATH + filename
	else:
		current_output_file = DEFAULT_OUTPUT
	
	return await _send_request(request_data)

# ENHANCED: Private method to handle request sending
func _send_request(request_data: Dictionary) -> bool:
	"""
	Send request to Python script
	"""
	if request_data.get("text", "") == "":
		push_error("Text cannot be empty")
		return false
	
	if is_waiting_for_audio:
		print("Already waiting for audio generation, skipping request")
		return false
	
	# Generate unique request ID
	current_request_id = "req_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000)
	request_data["request_id"] = current_request_id
	request_data["timestamp"] = Time.get_datetime_string_from_system()
	
	# Write request to file
	var file = FileAccess.open(REQUEST_FILE, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(request_data)
		file.store_string(json_string)
		file.flush()
		file.close()
		
		# Small delay to ensure file is written
		await get_tree().process_frame
		
		var request_type = request_data.get("type", "unknown")
		print("TTS Request sent (", request_type, "):")
		print("  Text: ", request_data["text"].substr(0, 50), "..." if request_data["text"].length() > 50 else "")
		if request_type == "predefined":
			print("  Voice: ", request_data.get("voice", "default"))
		elif request_type == "clone":
			print("  Voice file: ", request_data.get("voice_file_path", ""))
		print("  ID: ", current_request_id)
		
		is_waiting_for_audio = true
		return true
	else:
		push_error("Failed to write request file: " + REQUEST_FILE)
		return false

func check_status():
	"""Check Python status and handle audio when ready"""
	var file = FileAccess.open(STATUS_FILE, FileAccess.READ)
	if not file:
		return
	
	# Check if file is empty or being written to
	var file_size = file.get_length()
	if file_size == 0:
		file.close()
		return
	
	var content = file.get_as_text()
	file.close()
	
	# Check if content is valid (not empty or corrupted)
	if content == "" or content.length() == 0:
		return
	
	# Check if content looks like valid JSON
	if not content.begins_with("{") or not content.ends_with("}"):
		return
	
	var json = JSON.new()
	var parse_result = json.parse(content)
	
	# Check if JSON parsing was successful
	if parse_result != OK:
		print("JSON parse error: ", json.error_string)
		return
	
	var status_data = json.data
	if not status_data or typeof(status_data) != TYPE_DICTIONARY:
		return
	
	# Check if this is a new status update
	if status_data == last_status:
		return
	
	last_status = status_data.duplicate()
	
	var status = status_data.get("status", "unknown")
	var message = status_data.get("message", "")
	var progress = status_data.get("progress", 0)
	var request_id = status_data.get("last_request_id", "")
	
	# Emit status signal
	status_changed.emit(status, message, progress)
	
	# Only process status for our current request
	if request_id != current_request_id:
		return
	
	print("Status: ", status, " | ", message, " | Progress: ", progress, "%")
	
	match status:
		"ready":
			handle_audio_ready(message)
		"error":
			handle_audio_error(message)
		"processing":
			print("Processing: ", message)

func handle_audio_ready(message: String) -> void:
	"""Handle when audio is ready"""
	print("Audio ready: ", message)
	is_waiting_for_audio = false
	
	# Extract filename from current_output_file path
	var filename = current_output_file.get_file()
	audio_ready_to_read.emit(message, filename)
	
	# For backward compatibility, also emit the old signal
	if FileAccess.file_exists(current_output_file):
		audio_ready.emit(current_output_file, 0.0)  # Duration not available here

func handle_audio_error(error_message: String):
	"""Handle audio generation errors"""
	print("Audio Error: ", error_message)
	audio_error.emit(error_message)
	is_waiting_for_audio = false

# Enhanced convenience functions
func say(text: String, voice: String = "m-us-2"):
	"""Generate and prepare speech using predefined voice"""
	await generate_speech(text, voice)

func say_clone(text: String, voice_file_path: String):
	"""Generate and prepare speech using voice cloning"""
	await generate_speech_clone(text, voice_file_path)

func say_ljspeech(text: String):
	"""Generate and prepare speech using LJSpeech"""
	await generate_speech_ljspeech(text)

# Utility function to get the current output file path
func get_current_output_file() -> String:
	"""Get the path to the current/last generated audio file"""
	return current_output_file

# Function to check if audio file exists and is ready
func is_audio_file_ready() -> bool:
	"""Check if the current audio file exists and is ready to play"""
	return FileAccess.file_exists(current_output_file)

# Connect signals in code (optional)
func _connect_signals():
	audio_ready.connect(_on_audio_ready)
	audio_error.connect(_on_audio_error)
	status_changed.connect(_on_status_changed)
	audio_ready_to_read.connect(_on_audio_ready_to_read)

func _on_audio_ready(audio_file: String, duration: float):
	print("Signal: Audio ready - ", audio_file, " (", duration, "s)")

func _on_audio_error(error_message: String):
	print("Signal: Audio error - ", error_message)

func _on_status_changed(status: String, message: String, progress: int):
	print("Signal: Status - ", status, " | ", message, " | ", progress, "%")

func _on_audio_ready_to_read(message: String, filename: String):
	print("Signal: Audio ready to read - ", message, " | File: ", filename)
