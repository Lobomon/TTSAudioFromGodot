extends Node2D

var tts: StyleTTS2Enhanced  # Variable para guardar la instancia

func _ready() -> void:
	# Crear instancia
	tts = StyleTTS2Enhanced.new()
	add_child(tts) # ✅ IMPORTANTE: añadirlo a la escena para que pueda usar señales/await

	# Conectar la señal
	tts.connect("audio_ready_to_read", Callable(self, "_on_audio_ready"))

	# Usar una de sus funciones
	tts.generate_speech_clone("Hello this is an audio generated from godot in to a folder", "C:/tmp/uploads/my_voice.wav", 120, 15, 0.1, 0.9, 1.1, "cloned_output.wav")


func _on_audio_ready(message: String,audio: String) -> void:
	print("🎧 Señal recibida: ", message)
