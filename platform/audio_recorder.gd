extends Node
## Recorder interface. Implementations live in platform/ - per the plan, the
## ONLY layer allowed to touch AudioEffectRecord / JavaScriptBridge /
## getUserMedia. Everything above sees this contract and nothing else.
##
## Contract:
## - request_permission(): ask the platform for mic access; returns immediately
## - is_permission_pending(): the answer has not arrived yet
## - is_available(): device/permission preconditions look satisfiable
## - start_recording(): begins capture; false if unavailable or already running
## - stop_recording(): ends capture, returns 16-bit PCM WAV bytes
##   (ready for SoundBank.add_sound), or an EMPTY array on failure
## - release(): give the microphone back
class_name AudioRecorderBase


func is_available() -> bool:
	return false


func is_recording() -> bool:
	return false


func start_recording() -> bool:
	return false


func stop_recording() -> PackedByteArray:
	return PackedByteArray()


## Asks the platform for microphone access. Native platforms already have it by
## the time they are constructed, so this is a no-op there. On web it opens the
## browser's permission prompt, which is ASYNCHRONOUS: is_available() stays
## false until the guest taps "allow". Call it when the record UI opens (a user
## gesture - iOS Safari requires one) and poll is_permission_pending().
## Safe to call repeatedly.
func request_permission() -> void:
	pass


## True while the platform is still deciding. Lets the UI say "waiting for the
## microphone" instead of the flatly wrong "no microphone available".
func is_permission_pending() -> bool:
	return false


## True when the guest actively REFUSED - distinct from "there is no microphone"
## and from "this browser cannot record". The difference matters because a
## refusal is the only one of the three the guest can undo, and on iOS the
## decision is sticky: nothing in the game will ever prompt again, so the UI has
## to send them to their browser settings.
func is_permission_denied() -> bool:
	return false


## Hands the microphone back. On web this drops the getUserMedia stream, which
## is what turns the browser's recording indicator off; leaving it lit for the
## rest of the session reads as the game spying on you.
func release() -> void:
	pass