/* Isolated content-script world. Chat detection is scoped to interface controls. */
(() => {
  const clean = value => String(value || '').replace(/[\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, '').replace(/\s+/g, ' ').trim();
  const isoSeconds = date => date.toISOString().replace(/\.\d{3}Z$/, 'Z');
  const usageRoute = path => /^\/(?:[a-z]{2,3}(?:-[a-z]{2,8}){0,2}\/)?settings\/usage\/?$/i.test(path);
  const chatRoute = path => /^\/(?:[a-z]{2,3}(?:-[a-z]{2,8}){0,2}\/)?(?:chat\/[^/]+|new|project\/[^/]+)\/?$/i.test(path);
  // Exact interface labels on recognized Claude controls. A translated chat message
  // or a generic "allow" button cannot establish an action by itself.
  const uiLabels = {
    zh: {
      session:'当前会话|本次会话|当前工作阶段', weekly:'每周限额|每周使用量|每周限制|每周用量', all:'所有模型|全部模型', other:'额外用量|额外使用量|使用额度',
      used:'已使用|已用|已消耗', left:'剩余|可用', stop:'停止|停止生成|停止回复', thinking:'正在思考|思考中|Claude 正在思考', searching:'正在搜索网页|正在搜索网络|正在搜索互联网',
      once:'允许一次|仅允许一次|仅此一次', yes:'允许|批准', no:'拒绝|取消|不允许',
      heading:'工具权限|工具调用权限|工具授权请求|工具权限请求', request:/^Claude\s*(?:想要|希望|请求)(?:使用|调用|运行)(?:此|这个|一个)?(?:工具|连接器).{0,100}$/i
    },
    hi: {
      session:'वर्तमान सत्र|मौजूदा सत्र', weekly:'साप्ताहिक सीमाएँ|साप्ताहिक सीमा|साप्ताहिक उपयोग', all:'सभी मॉडल', other:'अतिरिक्त उपयोग|उपयोग क्रेडिट',
      used:'उपयोग किया गया|उपयोग हो चुका है|इस्तेमाल किया गया|उपयोग हुआ', left:'शेष|शेष है|उपलब्ध|बाकी',
      stop:'रोकें|जवाब रोकें|उत्तर रोकें|जनरेशन रोकें', thinking:'सोच रहा है|विचार कर रहा है|Claude सोच रहा है', searching:'वेब पर खोज रहा है|वेब खोज जारी है',
      once:'एक बार अनुमति दें|सिर्फ़ एक बार अनुमति दें', yes:'अनुमति दें|स्वीकृत करें|मंज़ूरी दें', no:'अस्वीकार करें|मना करें|रद्द करें',
      heading:'टूल की अनुमति|टूल के लिए अनुमति|टूल अनुमति अनुरोध|टूल की अनुमति आवश्यक है', request:/^Claude .*(?:टूल|कनेक्टर).*(?:उपयोग|इस्तेमाल|चलाना).*(?:चाहता है|चाहता है।)$/i
    },
    es: {
      session:'Sesión actual', weekly:'Límites semanales|Límite semanal|Uso semanal', all:'Todos los modelos', other:'Uso adicional|Créditos de uso',
      used:'utilizado|utilizada|utilizados|usado|usada|consumido|de uso', left:'restante|disponible', stop:'Detener|Detener respuesta|Detener la respuesta|Detener generación', thinking:'Pensando|Claude está pensando', searching:'Buscando en la web|Buscando en Internet',
      once:'Permitir una vez|Permitir solo esta vez|Permitir esta vez', yes:'Permitir|Aprobar', no:'Rechazar|Denegar|Cancelar|No permitir',
      heading:'Autorización de herramienta|Permiso de herramienta|Solicitud de permiso de herramienta|Permiso para usar la herramienta',
      request:/^Claude (?:quiere|desea) (?:usar|utilizar|ejecutar) (?:la |esta |una |el |este )?(?:herramienta|conector)\b.{0,130}$/i
    },
    ar: {
      session:'الجلسة الحالية|الجلسة الجارية', weekly:'الحدود الأسبوعية|حدود الاستخدام الأسبوعية|الاستخدام الأسبوعي|الحد الأسبوعي', all:'جميع النماذج|كل النماذج', other:'الاستخدام الإضافي|أرصدة الاستخدام',
      used:'مستخدم|مُستخدم|مستهلك|تم استخدام|تم استخدامه|تم استهلاك', left:'متبقٍ|متبقي|المتبقي|متاحة|متاح',
      stop:'إيقاف|إيقاف الرد|إيقاف إنشاء الرد|إيقاف التوليد', thinking:'جارٍ التفكير|جاري التفكير|يفكر Claude|يفكر', searching:'جارٍ البحث في الويب|جاري البحث في الويب|البحث في الويب',
      once:'السماح مرة واحدة|السماح هذه المرة|اسمح مرة واحدة', yes:'السماح|سماح|موافقة|الموافقة', no:'رفض|الرفض|إلغاء|عدم السماح',
      heading:'إذن الأداة|طلب إذن الأداة|طلب الموافقة على الأداة|إذن استخدام الأداة', request:/^(?:يريد|يرغب) (?:Claude|كلود) (?:في )?(?:استخدام|تشغيل) (?:الأداة|أداة|الموصل).{0,130}$/i
    },
    fr: {
      session:'Session actuelle|Session en cours', weekly:'Limites hebdomadaires|Limite hebdomadaire|Utilisation hebdomadaire', all:'Tous les modèles', other:'Utilisation supplémentaire|Crédits d’utilisation',
      used:'utilisé|utilisés|utilisée|consommé|consommée', left:'restant|restante|restants|disponible', stop:'Arrêter|Arrêter la réponse|Arrêter la génération', thinking:'Réflexion en cours|Claude réfléchit|Réflexion', searching:'Recherche sur le Web|Recherche sur le Web en cours',
      once:'Autoriser une fois|Autoriser cette fois|Autoriser cette fois-ci', yes:'Autoriser|Approuver', no:'Refuser|Annuler|Ne pas autoriser',
      heading:'Autorisation de l’outil|Autorisation de l’outil requise|Demande d’autorisation de l’outil', request:/^Claude (?:souhaite|veut) (?:utiliser|exécuter|appeler) (?:l'outil|cet outil|le connecteur|ce connecteur)\b.{0,130}$/i
    },
    bn: {
      session:'বর্তমান সেশন|চলতি সেশন', weekly:'সাপ্তাহিক সীমা|সাপ্তাহিক ব্যবহারের সীমা|সাপ্তাহিক ব্যবহার', all:'সব মডেল|সমস্ত মডেল|সকল মডেল', other:'অতিরিক্ত ব্যবহার|ব্যবহারের ক্রেডিট',
      used:'ব্যবহৃত|ব্যবহার করা হয়েছে|ব্যবহার হয়েছে|ব্যবহৃত হয়েছে', left:'অবশিষ্ট|বাকি|উপলভ্য',
      stop:'থামান|উত্তর থামান|থামুন|উত্তর বন্ধ করুন', thinking:'ভাবছে|চিন্তা করছে|Claude ভাবছে', searching:'ওয়েবে অনুসন্ধান করছে|ওয়েবে খোঁজা হচ্ছে',
      once:'একবার অনুমতি দিন|শুধু একবার অনুমতি দিন', yes:'অনুমতি দিন|অনুমোদন করুন', no:'প্রত্যাখ্যান করুন|বাতিল করুন|অনুমতি দেবেন না',
      heading:'টুলের অনুমতি|টুল ব্যবহারের অনুমতি|টুলের অনুমতির অনুরোধ', request:/^Claude .*(?:টুল|কানেক্টর).*ব্যবহার করতে চায়$/i
    },
    pt: {
      session:'Sessão atual', weekly:'Limites semanais|Limite semanal|Uso semanal|Utilização semanal', all:'Todos os modelos', other:'Uso adicional|Uso extra|Utilização adicional|Créditos de uso',
      used:'utilizado|utilizada|usado|usada|consumido|de uso', left:'restante|disponível', stop:'Parar|Interromper|Parar resposta|Interromper resposta|Parar de gerar', thinking:'Pensando|A pensar|Claude está pensando', searching:'Pesquisando na web|A pesquisar na web|Buscando na web',
      once:'Permitir uma vez|Permitir apenas desta vez|Permitir desta vez', yes:'Permitir|Aprovar', no:'Recusar|Rejeitar|Negar|Cancelar|Não permitir',
      heading:'Permissão da ferramenta|Permissão de ferramenta|Solicitação de permissão da ferramenta|Pedido de permissão da ferramenta',
      request:/^(?:O )?Claude (?:quer|deseja) (?:usar|utilizar|executar) (?:a |esta |uma |o |este )?(?:ferramenta|conector)\b.{0,130}$/i
    },
    id: {
      session:'Sesi saat ini|Sesi berjalan', weekly:'Batas mingguan|Batas penggunaan mingguan|Penggunaan mingguan', all:'Semua model', other:'Penggunaan tambahan|Kredit penggunaan',
      used:'digunakan|terpakai', left:'tersisa|tersedia', stop:'Hentikan|Hentikan respons|Hentikan jawaban', thinking:'Sedang berpikir|Claude sedang berpikir|Berpikir', searching:'Mencari di web|Menelusuri web',
      once:'Izinkan sekali|Izinkan satu kali|Izinkan kali ini', yes:'Izinkan|Setujui', no:'Tolak|Batalkan|Batal|Jangan izinkan',
      heading:'Izin alat|Permintaan izin alat|Persetujuan penggunaan alat', request:/^Claude (?:ingin|meminta untuk) (?:menggunakan|menjalankan) (?:alat|konektor)\b.{0,130}$/i
    },
    ur: {
      session:'موجودہ سیشن', weekly:'ہفتہ وار حدود|ہفتہ وار حد|ہفتہ وار استعمال', all:'تمام ماڈلز|تمام ماڈل', other:'اضافی استعمال|استعمال کے کریڈٹس',
      used:'استعمال ہوا|استعمال شدہ|استعمال کیا گیا|استعمال ہو چکا ہے', left:'باقی|باقی ہے|دستیاب',
      stop:'روکیں|جواب روکیں|جواب دینا روکیں', thinking:'سوچ رہا ہے|Claude سوچ رہا ہے', searching:'ویب پر تلاش جاری ہے|ویب پر تلاش کر رہا ہے',
      once:'ایک بار اجازت دیں|صرف ایک بار اجازت دیں', yes:'اجازت دیں|منظور کریں', no:'مسترد کریں|انکار کریں|منسوخ کریں',
      heading:'ٹول کی اجازت|ٹول کے استعمال کی اجازت|ٹول کی اجازت کی درخواست', request:/^Claude .*(?:ٹول|کنیکٹر).*استعمال کرنا چاہتا ہے$/i
    }
  };
  const key = value => clean(value).normalize('NFKC').toLowerCase().replace(/[’‘]/g, "'")
    .replace(/[.?!:؟。！？।]+$/, '').trim();
  // Only matched on a visible live work indicator in an actively generating turn.
  const actions = {
    planning: [
      'planning|making a plan|creating a plan', 'plant|plant die nächsten schritte|erstellt einen plan|planung läuft',
      '正在规划|正在制定计划|规划中', 'योजना बना रहा है|योजना तैयार कर रहा है',
      'planificando|creando un plan', 'جارٍ التخطيط|جاري التخطيط|يضع خطة',
      'planification en cours|élaboration du plan', 'পরিকল্পনা করছে|পরিকল্পনা তৈরি করছে',
      'planejando|a planear|criando um plano', 'sedang merencanakan|menyusun rencana', 'منصوبہ بنا رہا ہے|منصوبہ بندی جاری ہے'
    ],
    searching: [
      'researching|researching sources|searching sources', 'recherchiert|recherchiert quellen|durchsucht quellen',
      '正在研究|正在检索来源', 'शोध कर रहा है|स्रोतों में खोज रहा है',
      'investigando|buscando fuentes', 'جارٍ البحث عن مصادر|جاري إجراء البحث',
      'recherche de sources|recherche approfondie en cours', 'গবেষণা করছে|উৎস অনুসন্ধান করছে',
      'pesquisando fontes|a pesquisar fontes', 'sedang melakukan riset|mencari sumber', 'تحقیق جاری ہے|ذرائع تلاش کر رہا ہے'
    ],
    reading: [
      'reading file|reading a file|reading files|reading source|reading sources|reading document',
      'liest eine datei|liest dateien|liest quellen|liest ein dokument', '正在读取文件|正在阅读来源|正在阅读文档',
      'फ़ाइल पढ़ रहा है|फाइल पढ़ रहा है|स्रोत पढ़ रहा है', 'leyendo archivo|leyendo archivos|leyendo fuentes',
      'جارٍ قراءة الملف|جاري قراءة الملفات|جارٍ قراءة المصادر', 'lecture du fichier|lecture des fichiers|lecture des sources',
      'ফাইল পড়ছে|উৎস পড়ছে', 'lendo arquivos|lendo fontes|a ler ficheiros', 'membaca berkas|membaca file|membaca sumber',
      'فائل پڑھ رہا ہے|ذرائع پڑھ رہا ہے'
    ],
    executing: [
      'running code|executing code|running command|running a command', 'führt code aus|führt einen befehl aus|codeausführung läuft',
      '正在执行代码|正在运行代码|正在执行命令', 'कोड चला रहा है|कमांड चला रहा है',
      'ejecutando código|ejecutando un comando', 'جارٍ تشغيل الكود|جاري تنفيذ التعليمات البرمجية|جارٍ تنفيذ الأمر',
      'exécution du code|exécution de la commande', 'কোড চালাচ্ছে|কমান্ড চালাচ্ছে',
      'executando código|executando um comando|a executar código', 'menjalankan kode|menjalankan perintah', 'کوڈ چلا رہا ہے|کمانڈ چلا رہا ہے'
    ],
    drawing: [
      'creating a diagram|drawing a diagram|generating a diagram|creating an artifact|generating an artifact',
      'erstellt ein diagramm|zeichnet ein diagramm|erstellt ein artefakt', '正在绘制图表|正在生成图表|正在创建制品',
      'आरेख बना रहा है|आर्टिफैक्ट बना रहा है', 'creando un diagrama|creando un artefacto',
      'جارٍ إنشاء مخطط|جاري رسم مخطط|جارٍ إنشاء عنصر فني', 'création du diagramme|création d’un artefact',
      'ডায়াগ্রাম তৈরি করছে|আর্টিফ্যাক্ট তৈরি করছে', 'criando um diagrama|criando um artefato|a criar um diagrama',
      'membuat diagram|membuat artefak', 'خاکہ بنا رہا ہے|ڈایاگرام بنا رہا ہے'
    ]
  };
  const liveActions = new Map();
  for (const [action, languages] of Object.entries(actions)) {
    for (const variants of languages) for (const phrase of variants.split('|')) liveActions.set(key(phrase),action);
  }
  const labels = {};
  for (const vocabulary of Object.values(uiLabels)) {
    for (const [name, variants] of Object.entries(vocabulary)) {
      if (typeof variants !== 'string') continue;
      const entries = labels[name] || (labels[name] = new Set());
      for (const label of variants.split('|')) entries.add(key(label));
    }
  }
  const matchesLabel = (group, value) => labels[group].has(key(value));
  function digits(value) {
    return clean(value).normalize('NFKC').replace(/[٠-٩۰-۹०-९০-৯]/gu, digit => {
      const number = digit.codePointAt(0);
      const base = number >= 0x9e6 ? 0x9e6 : number >= 0x966 ? 0x966 : number >= 0x6f0 ? 0x6f0 : 0x660;
      return String(number - base);
    }).replace(/٪/g, '%').replace(/٫/g,'.');
  }
  const sectionMarkers = [
    ['session', /^(?:current session|aktuelle sitzung|laufende sitzung|5[- ]hour (?:session|limit)|5[- ]stunden[- ]limit)$/i],
    ['weekly', /^(?:weekly limits?|weekly usage|wöchentliche(?:s|n)? (?:limits?|nutzung)|wochenlimits?)$/i],
    ['all', /^(?:all models|alle modelle)(?:\s*\([^)]*\))?$/i],
    ['other', /^(?:(?:claude )?(?:opus|sonnet|haiku|fable)\b|extra usage\b|additional usage\b|usage credits\b|limit resets?\b|zusätzliche nutzung\b|nutzungsguthaben\b|nutzungscredits\b|limit zurücksetzen\b)/i]
  ];
  function marker(line) {
    if (matchesLabel('all', clean(line).normalize('NFKC').replace(/\s*\([^()]*\)$/, ''))) return 'all';
    if (/^(?:仅限?|solo|apenas|seulement|فقط|صرف|শুধু|केवल|khusus)\s*(?:claude )?(?:opus|sonnet|haiku|fable)\b/i.test(line)) return 'other';
    return sectionMarkers.find(([, pattern]) => pattern.test(line))?.[0]
      || ['session','weekly','all','other'].find(group => matchesLabel(group, line));
  }
  function percentLeft(valueLine) {
    const line = digits(valueLine);
    // A translation may place the usage label before or after the percentage.
    const quantity = /^(.*?)\s*(\d{1,3}(?:[.,]\d+)?)\s*%\s*(.*?)$/.exec(line);
    if (quantity && !(quantity[1] && quantity[3])) {
      const qualifier = (quantity[1] || quantity[3]).replace(/^[:：]\s*|\s*[:：]$/g,'');
      const amount = Number(quantity[2].replace(',', '.'));
      if (amount <= 100 && matchesLabel('left', qualifier)) return Math.round(amount);
      if (amount <= 100 && matchesLabel('used', qualifier)) return Math.round(100 - amount);
    }
    const match = /(?:^|[^\d.,-])(\d{1,3}(?:[.,]\d+)?)\s*%\s*(used|consumed|utili[sz]ed|verbraucht|genutzt|verwendet|ausgeschöpft|belegt|remaining|left|available|übrig|verbleibend|verfügbar)(?=$|[^\p{L}])/iu.exec(line);
    // On Claude’s usage cards a bare percentage also denotes consumption.
    const bare = /^([0-9]{1,3}(?:[.,]\d+)?)\s*%$/.exec(line);
    const number = match?.[1] ?? bare?.[1];
    if (number === undefined) return null;
    const value = Number(number.replace(',', '.'));
    if (value > 100) return null;
    return Math.round(/^(?:remaining|left|available|übrig|verbleibend|verfügbar)$/i.test(match?.[2] || '') ? value : 100 - value);
  }

  const dayIndex = {
    sun: 0, sunday: 0, so: 0, sonntag: 0, mon: 1, monday: 1, mo: 1, montag: 1,
    tue: 2, tues: 2, tuesday: 2, di: 2, dienstag: 2, wed: 3, wednesday: 3, mi: 3, mittwoch: 3,
    thu: 4, thurs: 4, thursday: 4, do: 4, donnerstag: 4, fri: 5, friday: 5, fr: 5, freitag: 5,
    sat: 6, saturday: 6, sa: 6, samstag: 6
  };
  const relativePhrases = [
    /^(?:resets?|resetting|wird|zurücksetzung|zurücksetzen|nächste zurücksetzung)\s+(?:in|nach)\s+(.+?)(?:\s+zurückgesetzt)?$/i,
    /^(?:将在|将于|在)?\s*(.+?)\s*(?:后重置|后重设)$/,
    /^(?:重置倒计时|距离重置还有)\s*[：:]?\s*(.+)$/,
    /^(.+?)\s+(?:में|के बाद)\s+रीसेट (?:होगा|होगी|होता है)$/,
    /^(?:se (?:restablece|restablecerá|reinicia|reiniciará)|restablecimiento|reinicio)\s+(?:dentro de|en)\s+(.+)$/,
    /^(?:(?:تتم|ستتم|يتم) )?(?:إعادة التعيين|إعادة الضبط|إعادة التعيين التالية)\s+(?:بعد|خلال)\s+(.+)$/,
    /^(?:réinitialisation|réinitialisé[e]?|se réinitialise|sera réinitialisé[e]?)\s+dans\s+(.+)$/,
    /^(.+?)\s+(?:পরে|পর)\s+রিসেট (?:হবে|হয়)$/,
    /^(?:redefine|redefinição|reinicia|reinicializa|será (?:redefinid[oa]|reiniciad[oa]))\s+(?:em|dentro de)\s+(.+)$/,
    /^(?:direset|diatur ulang|akan (?:direset|diatur ulang))\s+dalam\s+(.+)$/,
    /^(.+?)\s+(?:میں|کے بعد)\s+ری سیٹ (?:ہو گا|ہو گی|ہوگا|ہوگی|ہوتا ہے)$/
  ];
  // These mark an actual reset row even if its date or timezone cannot be resolved.
  const resetRows = [
    /^(?:重置时间|下次重置|将于|于)\s*[:：]?\s*(.+?)(?:重置)?$/,
    /^(.+?)\s+रीसेट (?:होगा|होगी|होता है)$/,
    /^(?:se (?:restablece|restablecerá|reinicia|reiniciará)|restablecimiento|reinicio)\s*:?\s+(.+)$/,
    /^(?:(?:تتم|ستتم|يتم) )?(?:إعادة التعيين|إعادة الضبط)\s*:?\s+(.+)$/,
    /^(?:réinitialisation|réinitialisé[e]?|se réinitialise|sera réinitialisé[e]?)\s*:?\s+(.+)$/,
    /^(.+?)\s+রিসেট (?:হবে|হয়)$/,
    /^(?:redefine|redefinição|reinicia|reinicializa|será (?:redefinid[oa]|reiniciad[oa]))\s*:?\s+(.+)$/,
    /^(?:direset|diatur ulang|akan (?:direset|diatur ulang))\s*:?\s+(.+)$/,
    /^(.+?)\s+ری سیٹ (?:ہو گا|ہو گی|ہوگا|ہوگی|ہوتا ہے)$/
  ];
  const durationUnits = [
    [86400, 'days|day|tagen|tage|tag|d|jours|jour|días|día|dias|dia|hari|天|日|दिन|أيام|يوم|দিন|دن'],
    [3600, 'hours|hour|hrs|hr|stunden|stunde|std|h|heures|heure|horas|hora|jam|小时|小時|घंटे|घंटों|घंटा|ساعات|ساعة|ঘণ্টা|ঘন্টা|گھنٹے|گھنٹہ'],
    [60, 'minutes|minute|minuten|minutos|minuto|mins|min|m|menit|分钟|分|मिनट|دقائق|دقيقة|মিনিট|منٹ'],
    [1, 'seconds|second|sekunden|sekunde|sek|secs|sec|s|secondes|seconde|segundos|segundo|detik|秒钟|秒|सेकंड|ثوانٍ|ثوان|ثانية|সেকেন্ড|سیکنڈ']
  ];
  const unitValues = new Map(durationUnits.flatMap(([multiplier, words]) => words.split('|').map(word => [word, multiplier])));
  const durationPart = new RegExp('^(\\d{1,4})\\s*(' + [...unitValues.keys()].sort((a,b) => b.length - a.length).join('|') + ')\\.?', 'u');
  function captured(expressions, value) {
    for (const expression of expressions) {
      const match = expression.exec(value);
      if (match) return match[1];
    }
    return null;
  }
  function durationTime(body, now) {
    let remaining = body.trim(), seconds = 0;
    const seenUnits = new Set();
    while (remaining) {
      const part = durationPart.exec(remaining);
      if (!part) return null;
      const unit = unitValues.get(part[2]);
      if (seenUnits.has(unit)) return null;
      seenUnits.add(unit);
      seconds += Number(part[1]) * unit;
      remaining = remaining.slice(part[0].length).trim();
      if (remaining) {
        const glue = /^(?:[,،、]\s*)?(?:(?:and|und|et|y|e|dan|और|এবং|اور)\s+|و\s*)?/u.exec(remaining)[0];
        remaining = remaining.slice(glue.length).trim();
        if (!remaining) return null;
      }
    }
    return seenUnits.size && seconds <= 8 * 86400 ? new Date(now.getTime() + seconds * 1000) : null;
  }
  let weekdays;
  function localAbsolute(input, now, kind) {
    // Accept a weekday and an unambiguous local clock. Unknown zones and free-form dates retain their label.
    const body = input.replace(/^(?:el |le |em |na |no |pada |يوم |在)/u,'')
      .replace(/(?:(?:^|\s+)(?:a las|às|à|pukul|الساعة|को|في)(?=\s|$)|[,،，])\s*/gu, ' ')
      .replace(/\s*(?:बजे|টায়|بجے)$/u, '').trim();
    const parts = /^(.*?)\s*(\d{1,2})(?::|\s*h\s*)(\d{2})\s*(am|pm|ص|م)?$/u.exec(body);
    if (!parts) return null;
    const [, prefix, hh, mm, period] = parts;
    let hour = Number(hh);
    const minute = Number(mm);
    if (hour > 23 || minute > 59 || (period && (hour < 1 || hour > 12))) return null;
    if (period) hour = hour % 12 + (period === 'pm' || period === 'م' ? 12 : 0);
    if (!weekdays) {
      weekdays = new Map();
      for (const locale of Object.keys(uiLabels)) {
        for (const width of ['long','short']) {
          const format = new Intl.DateTimeFormat(locale,{weekday:width});
          for (let index = 0; index < 7; index++) weekdays.set(key(format.format(new Date(2024,0,7 + index,12))),index);
        }
      }
    }
    const day = key(prefix);
    const date = new Date(now);
    date.setHours(hour,minute,0,0);
    if (weekdays.has(day)) {
      date.setDate(date.getDate() + (weekdays.get(day) - now.getDay() + 7) % 7);
      if (date < now) date.setDate(date.getDate() + 7);
    } else if (['明天','कल','mañana','غدًا','غدا','demain','আগামীকাল','amanhã','besok','کل'].includes(day)) {
      date.setDate(date.getDate() + 1);
    } else if (['今天','आज','hoy','اليوم',"aujourd'hui",'আজ','hoje','hari ini','آج'].includes(day)) {
      if (date < now) return null;
    } else if (!day && kind === 'session') {
      if (date < now) date.setDate(date.getDate() + 1);
    } else return null;
    return date;
  }
  function resetTime(label, now, kind) {
    const lower = key(digits(label));
    const duration = captured(relativePhrases, lower);
    if (duration !== null) return durationTime(duration, now);
    const local = captured(resetRows, lower);
    if (local !== null) return localAbsolute(local, now, kind);
    // Only known weekday/relative-day + clock forms. Unsupported dates remain verbatim
    // in resetLabel. Never project a time in an unrecognized timezone.
    let body = lower.replace(/^(?:resets?|resetting|wird|zurücksetzung|zurücksetzen|nächste zurücksetzung)\s*/i, '')
      .replace(/\s*(?:zurückgesetzt)\.?$/i, '').replace(/^[:\s]+/, '').trim();
    const m = /^(?:(?:on|am)\s+)?(?:(\p{L}+)\.?\s*[,·]?\s+)?(?:(?:at|um)\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|uhr)?$/iu.exec(body);
    if (!m) return null;
    let [, day, hourText, minuteText, period] = m;
    let hour = Number(hourText);
    const minute = Number(minuteText || 0);
    if (!minuteText && !period) return null;
    if (minute > 59 || hour > 23) return null;
    if (period === 'am' || period === 'pm') {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (period === 'pm' ? 12 : 0);
    }
    if (day === 'at' || day === 'um') day = undefined;
    const date = new Date(now);
    date.setHours(hour, minute, 0, 0);
    if (day && Object.hasOwn(dayIndex, day)) {
      date.setDate(date.getDate() + (dayIndex[day] - now.getDay() + 7) % 7);
      if (date < now) date.setDate(date.getDate() + 7);
    } else if (day === 'tomorrow' || day === 'morgen') {
      date.setDate(date.getDate() + 1);
    } else if (day === 'today' || day === 'heute') {
      if (date < now) return null;
    } else if (!day && kind === 'session') {
      if (date < now) date.setDate(date.getDate() + 1);
    } else return null;
    return date;
  }
  function usage(text, now = new Date()) {
    const groups = new Map();
    let card = null;
    let inWeekly = false;
    for (const line of text.split(/\n/).map(clean).filter(Boolean)) {
      const tag = marker(line);
      if (tag) {
        if (tag === 'session') { card = 'session'; inWeekly = false; }
        if (tag === 'weekly') { card = 'weekly'; inWeekly = true; }
        if (tag === 'all') card = inWeekly ? 'weekly' : null;
        if (tag === 'other') card = null;
        if (card && !groups.has(card)) groups.set(card, []);
        continue;
      }
      if (card) groups.get(card).push(line);
    }
    const windows = [];
    for (const [kind, lines] of groups) {
      const values = [...new Set(lines.map(percentLeft).filter(n => n !== null))];
      if (values.length !== 1) continue;
      const window = {kind, remainingPercent: values[0]};
      const label = lines.find(line => {
        if (line.length > 100 || digits(line).includes('%')) return false;
        const text = key(digits(line));
        return /^(?:resets?\b|resetting\b|wird\b.*zurückgesetzt|zurücksetzung\b|zurücksetzen\b|nächste zurücksetzung\b)/i.test(text)
          || captured(relativePhrases, text) !== null || captured(resetRows, text) !== null;
      });
      if (label) {
        window.resetLabel = label;
        const date = resetTime(label, now, kind);
        if (date) {
          window.resetAt = isoSeconds(date);
          if (captured(relativePhrases, key(digits(label))) !== null) window.resetApproximate = true;
        }
      }
      windows.push(window);
    }
    return windows;
  }
  const stopSelector = [
    'button[data-testid="stop-button"]', 'button[data-testid="stop-response"]',
    'button[data-testid="stop-response-button"]', 'button[data-testid="stop-generating"]',
    'button[data-testid="stop-generating-button"]', 'button[aria-label]', 'button[title]'
  ].join(',');
  function isStopButton(button) {
    const testid = button.getAttribute('data-testid') || '';
    if (/^stop-(?:button|(?:response|generating)(?:-button)?)$/i.test(testid)) return true;
    return ['aria-label', 'title'].some(attribute => matchesLabel('stop', button.getAttribute(attribute)) ||
      /^(?:stop(?: (?:claude|response|generating|generation|streaming))?|(?:antwort|generierung|ausgabe)(?: von claude)? (?:stoppen|abbrechen|anhalten)|stoppen)$/i.test(clean(button.getAttribute(attribute))));
  }
  const visible = element => element.getClientRects().length > 0 && element.getAttribute('aria-hidden') !== 'true'
    && !element.closest?.('[hidden], [inert], [aria-hidden="true"]')
    && (typeof element.checkVisibility !== 'function' || element.checkVisibility({checkVisibilityCSS: true, checkOpacity: true}));
  function activity(doc) {
    const stop = [...doc.querySelectorAll(stopSelector)].find(button => visible(button) && isStopButton(button));
    if (!stop) return 'idle';
    // Only UI status attributes. Conversation text and composer contents are never read.
    const statusSelectors = ['[role="status"][aria-label]', '[aria-live][aria-label]', '[data-is-streaming="true"][aria-label]',
      '[data-testid="tool-status"][data-state="running"][aria-label]', '[data-testid="tool-use-status"][data-state="running"][aria-label]'];
    let fallback = 'working';
    for (const status of doc.querySelectorAll(statusSelectors.join(','))) {
      if (!visible(status)) continue;
      const label = clean(status.getAttribute('aria-label')).replace(/[. …]+$/, '');
      const action = liveActions.get(key(label));
      if (action) return action;
      if (matchesLabel('searching', label) || /^(?:searching (?:the )?web|web search in progress|durchsucht das web|websuche läuft|suche im web)$/i.test(label)) {
        fallback = 'searching';
      } else if (fallback === 'working' && (matchesLabel('thinking', label)
                 || /^(?:thinking|claude is thinking|denkt nach|claude denkt nach|nachdenken)$/i.test(label))) {
        fallback = 'thinking';
      }
    }
    return fallback;
  }
  const promptIDs = ['tool-use-approval', 'tool-approval', 'tool-permission', 'tool-permission-request',
    'tool-approval-dialog', 'tool-permission-dialog', 'tool-use-permission', 'mcp-tool-approval', 'connector-tool-approval'];
  const promptSelector = ['dialog[open]', '[role="dialog"]', '[role="alertdialog"]', '[role="group"][aria-label]',
    ...promptIDs.map(id => '[data-testid="' + id + '"]')].join(',');
  const buttons = 'button, [role="button"]';
  const headings = 'h1, h2, h3, h4, [role="heading"], [data-testid="tool-permission-title"]';
  const messageText = 'pre, code, .prose, [contenteditable="true"], [role="textbox"], [data-testid="user-message"], [data-message-author-role="user"]';
  const once = /^(?:allow (?:just )?(?:once|this time)|approve once|(?:einmal(?:ig)?|dieses mal) (?:erlauben|zulassen|genehmigen))$/i;
  const yes = /^(?:allow|approve|erlauben|zulassen|genehmigen)$/i;
  const no = /^(?:deny|decline|reject|cancel|skip|ablehnen|verweigern|abbrechen|überspringen|nicht (?:erlauben|zulassen))$/i;
  function controlLabel(el) {
    return clean(el.getAttribute('aria-label') || el.innerText || el.textContent || '')
      .replace(/\s*(?:\(?\s*(?:ctrl|cmd|⌘|strg)\s*\+?\s*(?:enter|return|↵|⏎)\s*\)?)$/i, '').trim();
  }
  function toolHeading(value) {
    const s = clean(value);
    if (!s || s.length > 230) return false;
    if (matchesLabel('heading', s) || Object.values(uiLabels).some(v => v.request.test(key(s)))) return true;
    return /^(?:(?:tool|connector|mcp)[ -](?:use[ -])?(?:approval|permission)(?: request| required)?|(?:tool|werkzeug|konnektor|connector)[ -]?(?:freigabe|genehmigung|berechtigung)(?: erforderlich)?)[?!.:]?$/i.test(s)
      || /^(?:claude (?:wants|would like|is asking) to (?:use|run|call)|allow claude to (?:use|run|call)) (?:.{1,100} from .{1,90}|(?:the |this |an? )?(?:tool|connector)\b.{0,130})[?!.]?$/i.test(s)
      || /^claude (?:möchte|will) (?:.{1,100} (?:von|aus) .{1,90}|(?:das |ein |den |diesen )?(?:tool|werkzeug|konnektor|connector)\b.{0,120}) (?:verwenden|nutzen|aufrufen|ausführen)[?!.]?$/i.test(s);
  }
  function approvalPrompt(root) {
    if (!visible(root) || root.closest(messageText)) return false;
    const controls = root.querySelectorAll(buttons);
    if (controls.length < 2 || controls.length > 10) return false;
    const choices = Array.from(controls)
      .filter(b => !b.disabled && !b.closest(messageText) && b.getAttribute('aria-disabled') !== 'true' && visible(b)).map(controlLabel);
    if (!choices.some(label => once.test(label) || yes.test(label) || matchesLabel('once', label) || matchesLabel('yes', label)) || !choices.some(label => no.test(label) || matchesLabel('no', label))) return false;
    if (promptIDs.includes(root.getAttribute('data-testid')) || toolHeading(root.getAttribute('aria-label'))) return true;
    const labelled = (root.getAttribute('aria-labelledby') || '').split(/\s+/).filter(Boolean)
      .map(id => root.ownerDocument.getElementById(id)).filter(el => el && visible(el));
    if ([...labelled, ...root.querySelectorAll(headings)].some(el => !el.closest(messageText) && visible(el) && toolHeading(el.textContent))) return true;
    // Some headers style the tool and connector names with inline spans.
    return Array.from(root.querySelectorAll('p, div, span')).some(el =>
      el.firstChild?.nodeType === 3 && /^\s*(?:allow claude|(?:o )?claude|(?:يريد|يرغب) (?:Claude|كلود))/i.test(el.firstChild.nodeValue)
      && Array.from(el.children).every(child => /^(?:SPAN|STRONG|B|CODE|A|EM|I)$/.test(child.tagName))
      && !el.closest(messageText) && visible(el) && toolHeading(el.textContent));
  }
  function awaitingApproval(doc) {
    if (Array.from(doc.querySelectorAll(promptSelector)).some(approvalPrompt)) return true;
    // Inline connector cards can expose the same controls without a dialog role.
    // Check only a compact group containing a one-time choice and its own heading.
    for (const button of doc.querySelectorAll(buttons)) {
      const label = controlLabel(button);
      if (button.closest(messageText) || !(once.test(label) || matchesLabel('once', label)) || !visible(button)) continue;
      let parent = button.parentElement;
      for (let depth = 0; parent && depth < 5; depth++, parent = parent.parentElement) {
        if (parent.matches('main, body, html, article, form, [role="main"], [data-testid="user-message"], [data-is-streaming]')) break;
        if (approvalPrompt(parent)) return true;
      }
    }
    return false;
  }
  const api = {usageRoute, chatRoute, usage, resetTime, activity, awaitingApproval, isStopButton, isoSeconds};
  globalThis.ClawdSignals = api;
  if (typeof module !== 'undefined') module.exports = api;
})();
