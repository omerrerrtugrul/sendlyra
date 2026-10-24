/// W-02/W-03: tarayıcıya sunulan statik HTML sayfaları.
///
/// Sunucu `dart:io HttpServer` ile uygulama içinden çalışır; sayfalar
/// tek dosya, harici bağımlılık yok (yalnızca gömülü CSS/JS).
library;

/// Listede gösterilen dosya bilgisi.
class WebFileInfo {
  const WebFileInfo({required this.name, required this.size});

  final String name;
  final int size;
}

String _t(String locale, {required String tr, required String en}) =>
    locale == 'en' ? en : tr;

String _shell({
  required String locale,
  required String title,
  required String body,
  bool insecure = false,
}) {
  final warn = insecure
      ? '<div class="warn">⚠️ ${_t(locale,
              tr: 'Bu bağlantı şifrelenmemiş (HTTP). Yalnızca güvendiğiniz ağda kullanın.',
              en: 'This connection is not encrypted (HTTP). Use only on trusted networks.')}</div>'
      : '';
  return '''
<!doctype html>
<html lang="$locale">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
         background: #f6f7fb; color: #1c1e26; }
  @media (prefers-color-scheme: dark) {
    body { background: #14161c; color: #e8eaf0; }
    .card { background: #1d2029; }
    input, button { color: inherit; }
  }
  .wrap { max-width: 760px; margin: 0 auto; padding: 24px 16px 64px; }
  h1 { font-size: 1.35rem; display: flex; align-items: center; gap: 10px; }
  .card { background: #fff; border-radius: 16px; padding: 18px; margin: 14px 0;
          box-shadow: 0 1px 3px rgba(0,0,0,.08); }
  .warn { background: #b4530922; border: 1px solid #b45309; color: #b45309;
          padding: 10px 14px; border-radius: 12px; margin: 12px 0; font-size: .92rem; }
  .muted { opacity: .7; font-size: .9rem; }
  a { color: #4f6df5; text-decoration: none; }
  a:hover { text-decoration: underline; }
  ul.files { list-style: none; padding: 0; margin: 0; }
  ul.files li { display: flex; justify-content: space-between; align-items: center;
                gap: 12px; padding: 10px 4px; border-bottom: 1px solid #8883; }
  ul.files li:last-child { border-bottom: 0; }
  .btn { display: inline-block; border: 0; border-radius: 10px; padding: 9px 16px;
         font-size: .95rem; cursor: pointer; background: #4f6df5; color: #fff; }
  .btn.secondary { background: transparent; color: #4f6df5;
                   border: 1px solid #4f6df5; }
  input[type=password], input[type=text] { width: 100%; padding: 10px 12px;
    border-radius: 10px; border: 1px solid #8886; background: transparent; }
  .drop { border: 2px dashed #8886; border-radius: 14px; padding: 26px;
          text-align: center; transition: all .15s; }
  .drop.over { border-color: #4f6df5; background: #4f6df518; }
  .row { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
  .top { display: flex; justify-content: space-between; align-items: center; }
</style>
</head>
<body>
<div class="wrap">
  <h1>📡 SendLyra <span class="muted">${_t(locale, tr: 'Web paylaşımı', en: 'Web share')}</span></h1>
  $warn
  $body
</div>
</body>
</html>''';
}

/// W-04: PIN giriş sayfası.
String webLoginPage({required String locale, String? error}) {
  final err = (error == null || error.isEmpty)
      ? ''
      : '<div class="warn">⚠️ $error</div>';
  final body = '''
<div class="card">
  <p>${_t(locale, tr: 'Bu paylaşım PIN ile korunuyor.', en: 'This share is protected by a PIN.')}</p>
  $err
  <form method="post" action="/login" class="row">
    <input type="password" name="pin" placeholder="PIN" autofocus>
    <button class="btn" type="submit">${_t(locale, tr: 'Giriş', en: 'Unlock')}</button>
  </form>
</div>''';
  return _shell(
    locale: locale,
    title: 'SendLyra · PIN',
    body: body,
  );
}

/// W-02/W-03: ana sayfa — indirme listesi + yükleme alanı.
String webSharePage({
  required String locale,
  required String deviceName,
  required List<WebFileInfo> files,
  required List<String> uploads,
  bool insecure = false,
  bool pinEnabled = false,
}) {
  final fileItems = files.isEmpty
      ? '<li class="muted">${_t(locale, tr: 'Henüz paylaşılan dosya yok.', en: 'No shared files yet.')}</li>'
      : [
          for (var i = 0; i < files.length; i++)
            '<li><span>${_escape(files[i].name)} '
                '<span class="muted">· ${_size(files[i].size)}</span></span>'
                '<a class="btn secondary" href="/files/$i">'
                '${_t(locale, tr: 'İndir', en: 'Download')}</a></li>',
        ].join();

  final uploadItems = uploads.isEmpty
      ? ''
      : '<div class="card"><h3>${_t(locale, tr: 'Yüklenenler', en: 'Uploaded')}</h3>'
          '<ul class="files">'
          '${[for (final u in uploads) '<li><span>${_escape(u)}</span></li>'].join()}'
          '</ul></div>';

  final body = '''
<div class="card">
  <div class="top">
    <div>
      <strong>${_escape(deviceName)}</strong>
      <div class="muted">${_t(locale,
          tr: 'Aynı ağdaki bu cihazdan dosya alın ve gönderin.',
          en: 'Download and send files with this device on your network.')}</div>
    </div>
    ${files.isNotEmpty ? '<a class="btn" href="/all.zip">${_t(locale, tr: 'Tümünü indir (.zip)', en: 'Download all (.zip)')}</a>' : ''}
  </div>
  <ul class="files" style="margin-top:12px">$fileItems</ul>
</div>

<div class="card">
  <h3 style="margin-top:0">${_t(locale, tr: 'Dosya yükle', en: 'Send files')}</h3>
  <div class="drop" id="drop">
    <p>${_t(locale,
        tr: 'Dosyaları buraya sürükleyip bırakın ya da',
        en: 'Drag & drop files here or')}</p>
    <input type="file" id="picker" multiple>
    <p class="muted" id="status"></p>
  </div>
</div>

${pinEnabled ? '<form method="post" action="/logout"><button class="btn secondary" type="submit">${_t(locale, tr: 'Oturumu kapat', en: 'Log out')}</button></form>' : ''}
$uploadItems

<script>
const drop = document.getElementById('drop');
const picker = document.getElementById('picker');
const status = document.getElementById('status');
async function upload(file) {
  status.textContent = '… ' + file.name;
  const res = await fetch('/upload?name=' + encodeURIComponent(file.name),
      { method: 'POST', body: file });
  status.textContent = res.ok
      ? '✅ ' + file.name
      : '❌ ' + file.name + ' (' + res.status + ')';
}
async function uploadAll(files) { for (const f of files) await upload(f); }
picker.addEventListener('change', () => uploadAll(picker.files));
['dragover', 'dragenter'].forEach(ev =>
    drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.add('over'); }));
['dragleave', 'drop'].forEach(ev =>
    drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.remove('over'); }));
drop.addEventListener('drop', e => uploadAll(e.dataTransfer.files));
</script>''';

  return _shell(
    locale: locale,
    title: 'SendLyra',
    body: body,
    insecure: insecure,
  );
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _size(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
}
