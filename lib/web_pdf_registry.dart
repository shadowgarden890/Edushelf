import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

void registerWebPdfViewer() {
  ui_web.platformViewRegistry.registerViewFactory(
    'pdf-viewer-dynamic',
    (int viewId) {
      final iframe = html.IFrameElement()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#070D1E';
      return iframe;
    },
  );
}
