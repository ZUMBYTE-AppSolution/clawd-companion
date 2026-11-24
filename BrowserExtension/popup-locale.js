'use strict';

(() => {
  // Popup copy also serves Browser UI languages without a native manifest catalog.
  const messages = {
    "en": {
      "title": "Connect Claw’d",
      "checking": "Checking connection…",
      "code": "Pairing code from the Mac app",
      "connect": "Connect to Mac",
      "usage": "Open Claude usage",
      "forget": "Remove saved pairing",
      "note": "Claw’d follows Claude.ai in this browser. Open your account’s usage page to refresh your limits.",
      "token": "The app didn’t accept this code. Copy the current pairing code from Claw’d.",
      "offline": "Claw’d is offline. Open the app on this Mac and check its browser connection.",
      "rejected": "The Mac app declined the request. Check the browser connection in Claw’d.",
      "unpaired": "Ready to pair",
      "connected": "Connected to Claw’d on this Mac"
    },
    "de": {
      "title": "Claw’d verbinden",
      "checking": "Verbindung wird geprüft …",
      "code": "Kopplungscode aus der Mac-App",
      "connect": "Mit dem Mac verbinden",
      "usage": "Kontingent in Claude öffnen",
      "forget": "Gespeicherte Kopplung entfernen",
      "note": "Die Figur reagiert auf Claude.ai in diesem Browser. Für aktuelle Werte öffne die Nutzungsseite deines Kontos.",
      "token": "Die App hat diesen Code abgelehnt. Kopiere den aktuellen Kopplungscode aus Claw’d.",
      "offline": "Claw’d ist nicht erreichbar. Öffne die App auf diesem Mac und prüfe die Browser-Verbindung.",
      "rejected": "Die Mac-App hat die Anfrage abgelehnt. Prüfe die Browser-Verbindung in Claw’d.",
      "unpaired": "Bereit zum Koppeln",
      "connected": "Mit Claw’d auf diesem Mac verbunden"
    },
    "zh-Hans": {
      "title": "连接 Claw’d",
      "checking": "正在检查连接…",
      "code": "Mac 应用中的配对码",
      "connect": "连接到 Mac",
      "usage": "查看 Claude 用量",
      "forget": "移除已保存的配对",
      "note": "Claw’d 会跟随此浏览器中的 Claude.ai 活动。打开账户的用量页面即可刷新额度。",
      "token": "应用未接受此配对码。请从 Claw’d 复制当前的配对码。",
      "offline": "无法连接到 Claw’d。请在这台 Mac 上打开应用，并检查浏览器连接。",
      "rejected": "Mac 应用拒绝了请求。请在 Claw’d 中检查浏览器连接。",
      "unpaired": "可以配对了",
      "connected": "已连接到这台 Mac 上的 Claw’d"
    },
    "hi": {
      "title": "Claw’d से कनेक्ट करें",
      "checking": "कनेक्शन की जाँच हो रही है…",
      "code": "Mac ऐप का पेयरिंग कोड",
      "connect": "Mac से कनेक्ट करें",
      "usage": "Claude का उपयोग देखें",
      "forget": "सेव की गई पेयरिंग हटाएँ",
      "note": "Claw’d इस ब्राउज़र में Claude.ai की गतिविधि दिखाता है। उपयोग सीमाएँ अपडेट करने के लिए अपने खाते का उपयोग पेज खोलें।",
      "token": "ऐप ने यह कोड स्वीकार नहीं किया। Claw’d से मौजूदा पेयरिंग कोड कॉपी करें।",
      "offline": "Claw’d से कनेक्ट नहीं हो पा रहा है। इस Mac पर ऐप खोलें और उसका ब्राउज़र कनेक्शन जाँचें।",
      "rejected": "Mac ऐप ने अनुरोध अस्वीकार कर दिया। Claw’d में ब्राउज़र कनेक्शन जाँचें।",
      "unpaired": "पेयरिंग के लिए तैयार",
      "connected": "इस Mac पर Claw’d से कनेक्ट है"
    },
    "es": {
      "title": "Conectar Claw’d",
      "checking": "Comprobando la conexión…",
      "code": "Código de vinculación de la app para Mac",
      "connect": "Conectar al Mac",
      "usage": "Ver el uso de Claude",
      "forget": "Eliminar la vinculación guardada",
      "note": "Claw’d sigue la actividad de Claude.ai en este navegador. Abre la página de uso de tu cuenta para actualizar tus límites.",
      "token": "La app no ha aceptado el código. Copia el código de vinculación actual de Claw’d.",
      "offline": "No se puede conectar con Claw’d. Abre la app en este Mac y comprueba la conexión con el navegador.",
      "rejected": "La app para Mac ha rechazado la solicitud. Comprueba la conexión con el navegador en Claw’d.",
      "unpaired": "Listo para vincular",
      "connected": "Conectado a Claw’d en este Mac"
    },
    "ar": {
      "title": "الاتصال بـ Claw’d",
      "checking": "جارٍ التحقق من الاتصال…",
      "code": "رمز الإقران من تطبيق Mac",
      "connect": "الاتصال بجهاز Mac",
      "usage": "عرض استخدام Claude",
      "forget": "إزالة الإقران المحفوظ",
      "note": "يتابع Claw’d نشاط Claude.ai في هذا المتصفح. افتح صفحة الاستخدام في حسابك لتحديث حدود الاستخدام.",
      "token": "لم يقبل التطبيق هذا الرمز. انسخ رمز الإقران الحالي من Claw’d.",
      "offline": "تعذّر الاتصال بـ Claw’d. افتح التطبيق على جهاز Mac هذا وتحقق من اتصاله بالمتصفح.",
      "rejected": "رفض تطبيق Mac الطلب. تحقّق من اتصال المتصفح في Claw’d.",
      "unpaired": "جاهز للإقران",
      "connected": "متصل بـ Claw’d على جهاز Mac هذا"
    },
    "fr": {
      "title": "Connecter Claw’d",
      "checking": "Vérification de la connexion…",
      "code": "Code de jumelage de l’app Mac",
      "connect": "Connecter au Mac",
      "usage": "Voir l’utilisation de Claude",
      "forget": "Supprimer le jumelage enregistré",
      "note": "Claw’d suit l’activité de Claude.ai dans ce navigateur. Ouvrez la page d’utilisation de votre compte pour actualiser vos limites.",
      "token": "L’app a refusé ce code. Copiez le code de jumelage actuel dans Claw’d.",
      "offline": "Claw’d est inaccessible. Ouvrez l’app sur ce Mac et vérifiez sa connexion au navigateur.",
      "rejected": "L’app Mac a refusé la demande. Vérifiez la connexion au navigateur dans Claw’d.",
      "unpaired": "Prêt pour le jumelage",
      "connected": "Connecté à Claw’d sur ce Mac"
    },
    "bn": {
      "title": "Claw’d সংযুক্ত করুন",
      "checking": "সংযোগ পরীক্ষা করা হচ্ছে…",
      "code": "Mac অ্যাপের পেয়ারিং কোড",
      "connect": "Mac-এ সংযোগ করুন",
      "usage": "Claude-এর ব্যবহারের হিসাব দেখুন",
      "forget": "সংরক্ষিত পেয়ারিং সরান",
      "note": "Claw’d এই ব্রাউজারে Claude.ai-এর কার্যকলাপ দেখায়। ব্যবহারের সীমা হালনাগাদ করতে আপনার অ্যাকাউন্টের ব্যবহার পাতা খুলুন।",
      "token": "অ্যাপটি এই কোড গ্রহণ করেনি। Claw’d থেকে বর্তমান পেয়ারিং কোডটি কপি করুন।",
      "offline": "Claw’d-এর সঙ্গে সংযোগ করা যাচ্ছে না। এই Mac-এ অ্যাপটি খুলে ব্রাউজারের সংযোগ পরীক্ষা করুন।",
      "rejected": "Mac অ্যাপটি অনুরোধ প্রত্যাখ্যান করেছে। Claw’d-এ ব্রাউজারের সংযোগ পরীক্ষা করুন।",
      "unpaired": "পেয়ারিংয়ের জন্য প্রস্তুত",
      "connected": "এই Mac-এ Claw’d সংযুক্ত আছে"
    },
    "pt": {
      "title": "Conectar o Claw’d",
      "checking": "Verificando a conexão…",
      "code": "Código de pareamento do app para Mac",
      "connect": "Conectar ao Mac",
      "usage": "Ver uso do Claude",
      "forget": "Remover pareamento salvo",
      "note": "O Claw’d acompanha o Claude.ai neste navegador. Abra a página de uso da sua conta para atualizar os limites.",
      "token": "O app não aceitou esse código. Copie o código de pareamento atual do Claw’d.",
      "offline": "Não foi possível conectar ao Claw’d. Abra o app neste Mac e verifique a conexão com o navegador.",
      "rejected": "O app para Mac recusou a solicitação. Verifique a conexão com o navegador no Claw’d.",
      "unpaired": "Pronto para parear",
      "connected": "Conectado ao Claw’d neste Mac"
    },
    "id": {
      "title": "Hubungkan Claw’d",
      "checking": "Memeriksa koneksi…",
      "code": "Kode pemasangan dari aplikasi Mac",
      "connect": "Hubungkan ke Mac",
      "usage": "Lihat penggunaan Claude",
      "forget": "Hapus pemasangan tersimpan",
      "note": "Claw’d mengikuti aktivitas Claude.ai di peramban ini. Buka halaman penggunaan akun untuk memperbarui batas penggunaan.",
      "token": "Aplikasi menolak kode ini. Salin kode pemasangan terbaru dari Claw’d.",
      "offline": "Claw’d tidak dapat dijangkau. Buka aplikasi di Mac ini dan periksa koneksinya ke peramban.",
      "rejected": "Aplikasi Mac menolak permintaan. Periksa koneksi peramban di Claw’d.",
      "unpaired": "Siap dipasangkan",
      "connected": "Terhubung ke Claw’d di Mac ini"
    },
    "ur": {
      "title": "Claw’d سے جڑیں",
      "checking": "کنکشن چیک کیا جا رہا ہے…",
      "code": "Mac ایپ کا پیئرنگ کوڈ",
      "connect": "Mac سے جڑیں",
      "usage": "Claude کا استعمال دیکھیں",
      "forget": "محفوظ کردہ پیئرنگ ہٹائیں",
      "note": "Claw’d اس براؤزر میں Claude.ai کی سرگرمی دکھاتا ہے۔ استعمال کی حدود تازہ کرنے کے لیے اپنے اکاؤنٹ کا استعمال والا صفحہ کھولیں۔",
      "token": "ایپ نے یہ کوڈ قبول نہیں کیا۔ Claw’d سے موجودہ پیئرنگ کوڈ کاپی کریں۔",
      "offline": "Claw’d سے رابطہ نہیں ہو پا رہا۔ اس Mac پر ایپ کھولیں اور براؤزر کا کنکشن چیک کریں۔",
      "rejected": "Mac ایپ نے درخواست مسترد کر دی۔ Claw’d میں براؤزر کا کنکشن چیک کریں۔",
      "unpaired": "پیئرنگ کے لیے تیار",
      "connected": "اس Mac پر Claw’d سے کنکشن قائم ہے"
    },
    "pt-PT": {
      "title": "Conectar o Claw’d",
      "checking": "A verificar a ligação…",
      "code": "Código de emparelhamento da aplicação para Mac",
      "connect": "Conectar ao Mac",
      "usage": "Ver a utilização do Claude",
      "forget": "Remover o emparelhamento guardado",
      "note": "O Claw’d acompanha o Claude.ai neste navegador. Abra a página de utilização da sua conta para atualizar os limites.",
      "token": "A aplicação recusou o código. Copie o código de emparelhamento atual do Claw’d.",
      "offline": "Não foi possível contactar o Claw’d. Abra a aplicação neste Mac e verifique a ligação ao navegador.",
      "rejected": "A aplicação para Mac recusou o pedido. Verifique a ligação ao navegador no Claw’d.",
      "unpaired": "Pronto para emparelhar",
      "connected": "Ligação ao Claw’d neste Mac estabelecida"
    }
  };

  function select(preferences) {
    for (const tag of preferences) {
      if (typeof tag !== 'string' || !tag) continue;
      let locale;
      try { locale = new Intl.Locale(tag.replaceAll('_', '-')); }
      catch { continue; }
      const key = locale.language === 'zh' ? 'zh-Hans'
        : locale.language === 'pt' && locale.region === 'PT' ? 'pt-PT' : locale.language;
      if (!Object.hasOwn(messages, key)) continue;
      return {language:key, direction:key === 'ar' || key === 'ur' ? 'rtl' : 'ltr', strings:messages[key]};
    }
    return {language:'en', direction:'ltr', strings:messages.en};
  }

  globalThis.ClawdPopupLocale = {select};
})();
