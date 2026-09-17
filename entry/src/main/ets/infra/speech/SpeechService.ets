import { audio } from '@kit.AudioKit';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface SpeechCallbacks {
  onPartial: (text: string) => void;
  onFinal: (text: string) => void;
  onError: (message: string) => void;
}

/**
 * 端侧语音识别（Core Speech Kit，zh-CN）：AudioCapturer 采集 16k/16bit/单声道 PCM，
 * writeAudio 喂给识别引擎，onResult 回收文本。需 MICROPHONE 权限已授予。
 */
export class SpeechService {
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private capturer: audio.AudioCapturer | null = null;
  private sessionId: string = '';
  private listening: boolean = false;
  private lastText: string = '';
  private cb: SpeechCallbacks | null = null;

  isListening(): boolean {
    return this.listening;
  }

  currentText(): string {
    return this.lastText;
  }

  async start(cb: SpeechCallbacks): Promise<void> {
    if (this.listening) {
      return;
    }
    this.cb = cb;
    this.lastText = '';
    this.sessionId = `rb_${Date.now()}`;
    const createParams: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1
    };
    try {
      this.engine = await speechRecognizer.createEngine(createParams);
    } catch (err) {
      throw new Error('语音引擎创建失败，请检查系统支持');
    }
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (sessionId: string, eventMessage: string) => {},
      onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {},
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        this.lastText = result.result;
        const callback = this.cb;
        if (callback === null) {
          return;
        }
        if (result.isFinal) {
          callback.onFinal(result.result);
        } else {
          callback.onPartial(result.result);
        }
      },
      onComplete: (sessionId: string, eventMessage: string) => {
        this.listening = false;
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        this.listening = false;
        const callback = this.cb;
        if (callback !== null) {
          callback.onError(`识别出错 code=${errorCode} ${errorMessage}`);
        }
      }
    };
    this.engine.setListener(listener);

    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };
    const capturerInfo: audio.AudioCapturerInfo = {
      source: audio.SourceType.SOURCE_TYPE_MIC,
      capturerFlags: 0
    };
    const options: audio.AudioCapturerOptions = {
      streamInfo: streamInfo,
      capturerInfo: capturerInfo
    };
    try {
      this.capturer = await audio.createAudioCapturer(options);
    } catch (err) {
      this.listening = false;
      this.releaseEngine();
      throw new Error('麦克风启动失败');
    }
    this.capturer.on('readData', (buffer: ArrayBuffer) => {
      if (this.engine !== null && this.listening && buffer.byteLength > 0) {
        this.engine.writeAudio(this.sessionId, new Uint8Array(buffer));
      }
    });
    try {
      await this.capturer.start();
    } catch (err) {
      const e = err as BusinessError;
      await this.releaseCapturer();
      this.releaseEngine();
      throw new Error(`麦克风启动失败 code=${e.code}`);
    }
    this.listening = true;
    const startParams: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: {
        audioType: '0',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      }
    };
    this.engine.startListening(startParams);
  }

  async stop(): Promise<void> {
    if (this.engine !== null && this.listening) {
      try {
        this.engine.finish(this.sessionId);
      } catch (err) {
        // 引擎可能已结束
      }
    }
    await this.releaseCapturer();
    this.listening = false;
    this.releaseEngine();
  }

  /** 关闭识别引擎释放资源（每次会话重建，避免长期持有引擎实例）。 */
  private releaseEngine(): void {
    if (this.engine !== null) {
      try {
        this.engine.shutdown();
      } catch (err) {
        // 重复释放忽略
      }
      this.engine = null;
    }
  }

  private async releaseCapturer(): Promise<void> {
    if (this.capturer !== null) {
      try {
        await this.capturer.stop();
        await this.capturer.release();
      } catch (err) {
        // 重复释放忽略
      }
      this.capturer = null;
    }
  }
}
