import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private downloads: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  @State input: string = 'https://www.baidu.com';
  @State status: string = '正在打开网页';
  @State title: string = 'RoboPi 浏览器';
  @State downloadStatus: string = '';
  @State webReady: boolean = false;
  private initTimer: number = -1;

  aboutToAppear(): void {
    // Present the native browser controls before initializing ArkWeb on this board.
    this.initTimer = setTimeout(() => { this.webReady = true; }, 1500);
  }

  aboutToDisappear(): void {
    clearTimeout(this.initTimer);
  }

  private open(): void {
    const value = this.input.trim();
    if (!value) { return; }
    const url = /^https?:\/\//i.test(value) ? value :
      (/^[\w.-]+\.[a-z]{2,}([/:].*)?$/i.test(value) ? 'https://' + value :
        'https://www.baidu.com/s?wd=' + encodeURIComponent(value));
    this.input = url;
    this.controller.loadUrl(url);
  }

  private configureDownloads(): void {
    this.downloads.onBeforeDownload((item: webview.WebDownloadItem) => {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const name = item.getSuggestedFileName().replace(/[^\w.\u4e00-\u9fff-]/g, '_') || 'download';
      const path = context.filesDir + '/' + Date.now().toString() + '-' + name;
      this.downloadStatus = '下载中：' + name;
      item.start(path);
    });
    this.downloads.onDownloadFinish((item: webview.WebDownloadItem) => {
      this.downloadStatus = '已保存：' + item.getFullPath();
    });
    this.downloads.onDownloadFailed((item: webview.WebDownloadItem) => {
      this.downloadStatus = '下载失败：' + item.getLastErrorCode().toString();
    });
    this.controller.setDownloadDelegate(this.downloads);
  }

  build() {
    Column() {
      Text(this.title).fontSize(16).maxLines(1).padding(8).width('100%')
      Row({ space: 6 }) {
        TextInput({ text: this.input, placeholder: '输入网址或搜索内容' })
          .id('browser-address').layoutWeight(1).fontSize(16)
          .onChange((value: string) => { this.input = value; })
          .onSubmit(() => { this.open(); })
        Button('打开').id('browser-go').onClick(() => { this.open(); })
      }.padding({ left: 8, right: 8 }).width('100%')
      Row({ space: 12 }) {
        Button('清空').id('browser-clear').onClick(() => { this.input = ''; })
        Button('后退').onClick(() => {
          if (this.controller.accessBackward()) { this.controller.backward(); }
        })
        Button('前进').onClick(() => {
          if (this.controller.accessForward()) { this.controller.forward(); }
        })
        Button('刷新').onClick(() => { this.controller.refresh(); })
        Button('首页').onClick(() => {
          this.input = 'https://www.baidu.com'; this.open();
        })
      }.padding(8).width('100%')
      Text(this.status).fontSize(12).maxLines(2).width('100%').padding({ left: 8, right: 8 })
      if (this.downloadStatus) {
        Text(this.downloadStatus).fontSize(12).width('100%').padding(8)
      }
      if (this.webReady) {
      Column() {
      Web({ src: 'https://www.baidu.com', controller: this.controller, renderMode: RenderMode.ASYNC_RENDER })
        .id('browser-web').width('100%').height('100%')
        .javaScriptAccess(true).domStorageAccess(true)
        .onControllerAttached(() => { this.configureDownloads(); })
        .onAppear(() => { this.controller.onActive(); })
        .onPageBegin(() => { this.status = '正在加载…'; })
        .onPageEnd((event) => {
          if (event) { this.input = event.url; }
          this.controller.onActive();
          this.status = '加载完成';
        })
        .onTitleReceive((event) => {
          if (event) { this.title = event.title; }
        })
        .onErrorReceive((event) => {
          if (event && event.request.isMainFrame()) {
            this.status = '加载失败：' + event.error.getErrorInfo();
          }
        })
        .onSslErrorEventReceive((event) => {
          if (event) { event.handler.handleCancel(); }
          this.status = '证书校验失败，请检查网络及系统证书';
        })
      }.layoutWeight(1).width('100%')
      } else {
        Text('正在启动网页引擎…').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor('#F4F6F8')
  }
}
