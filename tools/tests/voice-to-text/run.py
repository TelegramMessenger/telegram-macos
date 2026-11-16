from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
chat = root / 'packages/ChatUI'
controller = (chat / 'Sources/ChatUI/ChatController.swift').read_text()
host = controller[controller.index('extension ChatControllerView: ChatVoiceTranscriptionHost {'):]
fixture = Path(__file__).with_name('TransitionTests.swift').read_text().replace('__HOST__', host)
text_tests = (chat / 'Tests/ChatUITests/ChatInputDictationTextTests.swift').read_text().replace('@testable import ChatUI\n', '')

def source_block(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    index = opening + 1
    while depth:
        depth += (source[index] == '{') - (source[index] == '}')
        index += 1
    return source[start:index]

coordinator = (chat / 'Sources/ChatUI/ChatVoiceTranscription.swift').read_text()
listening_tests = Path(__file__).with_name('ListeningTests.swift').read_text()
for placeholder, signature in [('__RECORDING_STOPPED__', 'func recordingStopped()'), ('__PERFORM__', 'func perform('), ('__ENGINE_FINISHED__', 'private func engineFinished('), ('__STOP_FOR_NAVIGATION__', 'func stopForNavigation()')]:
    listening_tests = listening_tests.replace(placeholder, source_block(coordinator, signature))
for placeholder, signature in [('__WINDOW_STOP__', 'public override func windowDidResignKey()'), ('__CHAT_STOP__', 'public override func viewWillDisappear('), ('__DETACH_STOP__', 'public override func readyToDetach()')]:
    method = source_block(controller, signature)
    listening_tests = listening_tests.replace(placeholder, next(line.strip() for line in method.splitlines() if 'voiceTranscription?.stopForNavigation()' in line))
escape = source_block(controller, 'public override func escapeKeyAction()')
listening_tests = listening_tests.replace('__ESCAPE__', source_block(escape, 'if let transcription = chatInteraction.voiceTranscription, transcription.isActive'))
cursor_tests = Path(__file__).with_name('CursorTests.swift').read_text()
for placeholder, signature in [('__COMPOSER_DID_UPDATE__', 'func composerDidUpdate('), ('__MAKE_INSERTION__', 'private func makeInsertion('), ('__UPDATE_COMPOSER__', 'private func updateComposer()')]:
    cursor_tests = cursor_tests.replace(placeholder, source_block(coordinator, signature))
cursor_tests = cursor_tests.replace('__PREPARE_COMPOSER__', source_block(coordinator, 'private func prepareComposer()').replace('private ', ''))
input_view = (chat / 'Sources/ChatUI/ChatInputView.swift').read_text()
width_tests = Path(__file__).with_name('WidthTests.swift').read_text()
for placeholder, signature in [('__IS_SEND_IN_FIELD__', 'var isSendButtonInField:'), ('__SEND_SLOT__', 'private func sendSlot('), ('__UPDATE_SEND_BUTTON__', 'private func updateSendButton('), ('__SET_TRANSCRIBING__', 'func setTranscribing(')]:
    width_tests = width_tests.replace(placeholder, source_block(input_view, signature))
cursor_tests = cursor_tests.replace('__UPDATE_SELECTION__', source_block(input_view, 'private func updateTranscriptionSelection('))
growth_tests = Path(__file__).with_name('InputGrowthTests.swift').read_text().replace('__INPUT_DID_UPDATE__', source_block(input_view, 'textInteractions.inputDidUpdate = {'))
input_text_view = (root / 'packages/InputView/Sources/InputView/ChatInputTextView.swift').read_text()
anchor_tests = Path(__file__).with_name('InputAnchorTests.swift').read_text().replace('__TEXT_FRAME__', source_block(input_text_view, 'static func textFrame('))
transcription_view = (chat / 'Sources/ChatUI/ChatVoiceTranscriptionView.swift').read_text()
glow_tests = Path(__file__).with_name('GlowTests.swift').read_text().replace('__GLOW__', source_block(transcription_view, 'final class ChatVoiceTranscriptionView: View').replace('final class ChatVoiceTranscriptionView:', 'final class TestedGlowView:'))

recording_view = (chat / 'Sources/ChatUI/ChatInputRecordingView.swift').read_text()
overlay = source_block(recording_view, 'private func showOverlay(')
auto_start = overlay[overlay.index('        if recorder.autohold {'):overlay.rfind('    }')]
state_update = source_block(input_view, 'public func needUpdateChatState(')
morph_policy = state_update[state_update.index('        let startsDictation: Bool'):state_update.index('        let isInputState')]
activation = state_update[state_update.rfind('        CATransaction.commit()') + len('        CATransaction.commit()'):state_update.rfind('    }')]
end = source_block(recording_view, 'private func endTranscribing()')
end_dictation = end[end.index('{') + 1:end.index('        deleteButton.setAccessibilityLabel')]
dictation_start_tests = Path(__file__).with_name('DictationStartTests.swift').read_text()
for placeholder, code in [('__AUTO_START__', auto_start), ('__START_DICTATION__', source_block(recording_view, 'func startDictation()')), ('__ACTIVATE__', activation), ('__MORPH_POLICY__', morph_policy), ('__END_DICTATION__', end_dictation)]:
    dictation_start_tests = dictation_start_tests.replace(placeholder, code)
recording_source = (chat / 'Sources/ChatUI/ChatDictationRecordingSource.swift').read_text()
source_start = source_block(recording_source, 'func start(')
snapshot_callback = source_start[source_start.index('                guard let self'):source_start.index('            }))')]
language_tests = Path(__file__).with_name('LanguageSwitchTests.swift').read_text()
for placeholder, code in [('__RESTART__', source_block(coordinator, 'private func restartForLanguageChange()')), ('__MAKE_INSERTION__', source_block(coordinator, 'private func makeInsertion(')), ('__UPDATE_COMPOSER__', source_block(coordinator, 'private func updateComposer()')), ('__SOURCE_INIT__', source_block(recording_source, 'init(audio:')), ('__RECEIVE__', source_block(recording_source, 'private func receive(')), ('__FEED__', source_block(recording_source, 'private func feed(snapshot:')), ('__DECODE__', source_block(recording_source, 'private func decode(')), ('__SNAPSHOT__', snapshot_callback)]:
    language_tests = language_tests.replace(placeholder, code.replace('private ', ''))
hold = source_block(recording_view, 'private func hold(')
mouse_handler = source_block(hold, 'let proccessMouseUp:')
click_tests = Path(__file__).with_name('ClickTests.swift').read_text().replace('__MOUSE_HANDLER__', mouse_handler.replace('KeyHandlerResult', 'RecordingClickResult'))
send_button = (chat / 'Sources/ChatUI/ChatInputSendButton.swift').read_text()
waveform_tests = Path(__file__).with_name('WaveformTests.swift').read_text().replace('__ACTIVATE_SEND__', source_block(send_button, 'private func activateSend()').replace('private ', ''))

flight_tests = Path(__file__).with_name('ButtonFlightTests.swift').read_text()
animation_utils = (root / 'packages/TGUIKit/Sources/CAAnimationUtils.swift').read_text()
completion = source_block(animation_utils, 'public class CALayerAnimationDelegate:') + '\n' + source_block(animation_utils, 'public extension CAAnimation {')
for placeholder, code in [('__ANIMATION_COMPLETION__', completion), ('__SET_DICTATING__', source_block(send_button, 'func setDictating(')), ('__DICTATION_APPEARANCE__', source_block(send_button, 'private func updateDictationAppearance()')), ('__FINISH_DICTATION__', source_block(send_button, 'private func finishDictationTransition()')), ('__PLANE_FLIGHT__', source_block(send_button, 'private func animatePlaneFlight()').replace('ChatInputSendButton.', 'FlightButton.')), ('__BUTTON_FLIGHT__', source_block(send_button, 'func animateDictationTransition(').replace('ChatInputSendButton.', 'FlightButton.')), ('__CANCEL_FLIGHT__', source_block(send_button, 'private func cancelDictationTransition()')), ('__DETACH_FLIGHT__', source_block(send_button, 'public override func viewDidMoveToWindow()')), ('__CAPTURE_ORIGIN__', source_block(recording_view, 'private func dictationButtonOrigin()').replace('private ', ''))]:
    flight_tests = flight_tests.replace(placeholder, code)

shortcut_tests = Path(__file__).with_name('ShortcutTests.swift').read_text().replace('__RECORDING_SHORTCUT__', source_block(controller, 'private func startRecordingShortcut()').replace('private ', '').replace('KeyHandlerResult', 'ShortcutResult'))

with tempfile.TemporaryDirectory(prefix='voice-to-text-') as temporary:
    directory = Path(temporary)
    (directory / 'Tests').mkdir()
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "VoiceToText", platforms: [.macOS(.v10_15)], targets: [.testTarget(name: "VoiceToTextTests", path: "Tests")])
''')
    (directory / 'Tests/LanguageSwitchTests.swift').write_text(language_tests)
    (directory / 'Tests/ClickTests.swift').write_text(click_tests)
    (directory / 'Tests/DictationStartTests.swift').write_text(dictation_start_tests)
    (directory / 'Tests/TransitionTests.swift').write_text(fixture)
    (directory / 'Tests/ListeningTests.swift').write_text(listening_tests)
    (directory / 'Tests/ShortcutTests.swift').write_text(shortcut_tests)
    (directory / 'Tests/WidthTests.swift').write_text(width_tests)
    (directory / 'Tests/GlowTests.swift').write_text(glow_tests)
    (directory / 'Tests/CursorTests.swift').write_text(cursor_tests)
    (directory / 'Tests/InputGrowthTests.swift').write_text(growth_tests)
    (directory / 'Tests/InputAnchorTests.swift').write_text(anchor_tests)
    (directory / 'Tests/TextTests.swift').write_text(text_tests)
    (directory / 'Tests/TextEffect.swift').write_text((chat / 'Sources/ChatUI/ChatDictationTextEffect.swift').read_text())
    (directory / 'Tests/TextEffectTests.swift').write_text(Path(__file__).with_name('TextEffectTests.swift').read_text())
    (directory / 'Tests/Waveform.swift').write_text((chat / 'Sources/ChatUI/ChatDictationWaveform.swift').read_text())
    (directory / 'Tests/Aura.swift').write_text((chat / 'Sources/ChatUI/ChatDictationAura.swift').read_text())
    (directory / 'Tests/WaveformView.swift').write_text((chat / 'Sources/ChatUI/ChatDictationWaveformView.swift').read_text().replace('import TGUIKit\n', ''))
    (directory / 'Tests/WaveformTests.swift').write_text(waveform_tests)
    (directory / 'Tests/ButtonFlightTests.swift').write_text(flight_tests)
    (directory / 'Tests/DictationText.swift').write_text((chat / 'Sources/ChatUI/ChatInputDictationText.swift').read_text())
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
