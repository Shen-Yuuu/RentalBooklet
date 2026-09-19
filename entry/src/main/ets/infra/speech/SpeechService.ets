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
  /** stop() 已发出 finish、正在等 onComplete 回调期间为 true（期间快速重启需强制释放旧资源）。 */
  private stopping: boolean = false;
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
      if (!this.stopping) {
        return;
      }
      // 上一会话在等 onComplete 期间被快速重启：强制释放旧资源后开新会话
      this.listening = false;
      await this.releaseCapturer();
      this.releaseEngine();
    }
    this.stopping = false;
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
        // 会话结束（含 60s 到点/静音超时自动结束）：立即释放麦克风与引擎。
        // 否则麦克风持续占用（隐私指示器常亮），下次 start 覆盖引用造成旧实例泄漏。
        this.listening = false;
        this.stopping = false;
        void this.releaseCapturer();
        this.releaseEngine();
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        this.listening = false;
        this.stopping = false;
        void this.releaseCapturer();
        this.releaseEngine();
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
    if (!this.listening) {
      // 已自动结束的资源在 onComplete/onError 中释放；此处兜底确保无残留
      await this.releaseCapturer();
      this.releaseEngine();
      return;
    }
    this.stopping = true;
    let finishOk = false;
    try {
      if (this.engine !== null) {
        this.engine.finish(this.sessionId);
        finishOk = true;
      }
    } catch (err) {
      // 引擎可能已结束
    }
    if (!finishOk) {
      this.listening = false;
      this.stopping = false;
      await this.releaseCapturer();
      this.releaseEngine();
      return;
    }
    // finish 是异步结算信号：等 onResult(isFinal)/onComplete 回调后再统一释放，
    // 立即 shutdown 会把用户最后一段话的识别结果丢掉；2s 兜底防引擎未回调导致资源悬挂。
    const sid = this.sessionId;
    setTimeout(() => {
      if (this.listening && this.stopping && this.sessionId === sid) {
        this.listening = false;
        this.stopping = false;
        void this.releaseCapturer();
        this.releaseEngine();
      }
    }, 2000);
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
