'use strict';
process.env.TZ = 'Europe/Berlin';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {usage,resetTime,chatRoute,usageRoute,activity,awaitingApproval} = require('../BrowserExtension/signals');
const observed = new Date('2026-11-24T09:00:00Z');
const locales = [
  {tag:'zh-Hans',session:'当前会话',week:'每周限额',all:'所有模型',used:'已使用 ３５％',left:'剩余 80%',relative:'将在 2 小时 15 分钟后重置',absolute:'重置时间：周五 15:30',stop:'停止生成',think:'正在思考',search:'正在搜索网页',title:'工具权限请求',choice:'允许一次',decline:'拒绝'},
  {tag:'hi',session:'वर्तमान सत्र',week:'साप्ताहिक सीमाएँ',all:'सभी मॉडल',used:'३५% उपयोग किया गया',left:'८०% शेष',relative:'२ घंटे १५ मिनट में रीसेट होगा',absolute:'शुक्रवार को १५:३० बजे रीसेट होगा',stop:'उत्तर रोकें',think:'सोच रहा है',search:'वेब पर खोज रहा है',title:'टूल के लिए अनुमति',choice:'एक बार अनुमति दें',decline:'अस्वीकार करें'},
  {tag:'es',session:'Sesión actual',week:'Límites semanales',all:'Todos los modelos',used:'35 % utilizado',left:'80 % restante',relative:'Se restablece en 2 horas y 15 minutos',absolute:'Se restablece el viernes a las 15:30',stop:'Detener la respuesta',think:'Pensando',search:'Buscando en la web',title:'Autorización de herramienta',choice:'Permitir una vez',decline:'Denegar'},
  {tag:'ar',session:'الجلسة الحالية',week:'الحدود الأسبوعية',all:'جميع النماذج',used:'تم استخدام ٣٥٪؜',left:'٨٠٪ متبقي',relative:'تتم إعادة التعيين بعد ٢ ساعة و١٥ دقيقة',absolute:'تتم إعادة التعيين يوم الجمعة الساعة ١٥:٣٠',stop:'إيقاف الرد',think:'جارٍ التفكير',search:'جارٍ البحث في الويب',title:'طلب إذن الأداة',choice:'السماح مرة واحدة',decline:'رفض'},
  {tag:'fr',session:'Session actuelle',week:'Limites hebdomadaires',all:'Tous les modèles',used:'35 % utilisé',left:'80 % restant',relative:'Réinitialisation dans 2 heures et 15 minutes',absolute:'Réinitialisation le vendredi à 15:30',stop:'Arrêter la réponse',think:'Réflexion en cours',search:'Recherche sur le Web',title:'Demande d’autorisation de l’outil',choice:'Autoriser une fois',decline:'Refuser'},
  {tag:'bn',session:'বর্তমান সেশন',week:'সাপ্তাহিক সীমা',all:'সব মডেল',used:'৩৫% ব্যবহৃত',left:'৮০% বাকি',relative:'২ ঘণ্টা ১৫ মিনিট পরে রিসেট হবে',absolute:'শুক্রবার ১৫:৩০ টায় রিসেট হবে',stop:'উত্তর থামান',think:'চিন্তা করছে',search:'ওয়েবে অনুসন্ধান করছে',title:'টুল ব্যবহারের অনুমতি',choice:'একবার অনুমতি দিন',decline:'প্রত্যাখ্যান করুন'},
  {tag:'pt-BR',session:'Sessão atual',week:'Limites semanais',all:'Todos os modelos',used:'35 % usado',left:'80 % restante',relative:'Reinicia em 2 horas e 15 minutos',absolute:'Reinicia na sexta-feira às 15:30',stop:'Parar resposta',think:'Pensando',search:'Pesquisando na web',title:'Permissão da ferramenta',choice:'Permitir uma vez',decline:'Recusar'},
  {tag:'id',session:'Sesi saat ini',week:'Batas mingguan',all:'Semua model',used:'35% digunakan',left:'80% tersisa',relative:'Diatur ulang dalam 2 jam dan 15 menit',absolute:'Diatur ulang pada Jumat pukul 15:30',stop:'Hentikan respons',think:'Sedang berpikir',search:'Menelusuri web',title:'Izin alat',choice:'Izinkan sekali',decline:'Tolak'},
  {tag:'ur',session:'موجودہ سیشن',week:'ہفتہ وار حدود',all:'تمام ماڈلز',used:'۳۵٪ استعمال ہوا',left:'۸۰٪ باقی',relative:'۲ گھنٹے ۱۵ منٹ میں ری سیٹ ہوگا',absolute:'جمعہ ۱۵:۳۰ بجے ری سیٹ ہوگا',stop:'جواب روکیں',think:'سوچ رہا ہے',search:'ویب پر تلاش جاری ہے',title:'ٹول کی اجازت',choice:'ایک بار اجازت دیں',decline:'مسترد کریں'}
];
function element(text, attrs = {}) {
  return {getAttribute:k=>attrs[k]??null,getClientRects:()=>[{}],closest:()=>null,innerText:text,textContent:text,
    parentElement:null,querySelectorAll:()=>[]};
}
for (const locale of locales) {
  test(locale.tag+' recognizes scoped usage and resolves unambiguous local and approximate resets',() => {
    assert.ok(usageRoute('/'+locale.tag+'/settings/usage'));
    assert.ok(chatRoute('/'+locale.tag+'/chat/example'));
    const text = [locale.session,locale.used,locale.relative,locale.week,locale.all,locale.left,locale.absolute].join('\n');
    assert.deepEqual(usage(text,observed),[
      {kind:'session',remainingPercent:65,resetLabel:locale.relative,resetAt:'2026-11-24T11:15:00Z',resetApproximate:true},
      {kind:'weekly',remainingPercent:80,resetLabel:locale.absolute,resetAt:'2026-11-27T14:30:00Z'}
    ]);
  });
  test(locale.tag+' binds activity to a stop control and approval to a tool-specific decision',() => {
    const stop = element('',{'aria-label':locale.stop});
    const status = element('',{'aria-label':locale.think});
    const page = {querySelectorAll:sel=>sel.includes('button') ? [stop] : [status]};
    assert.equal(activity(page),'thinking');
    status.getAttribute = ()=>locale.search;
    assert.equal(activity(page),'searching');
    const dialog = element('',{'aria-label':locale.title});
    dialog.querySelectorAll = selector => selector.startsWith('button') ? [element(locale.choice),element(locale.decline)] : [];
    const decisions = {querySelectorAll:sel=>sel.startsWith('button')?[]:[dialog]};
    assert.equal(awaitingApproval(decisions),true);
    dialog.getAttribute=()=>null;
    assert.equal(awaitingApproval(decisions),false);
  });
}
test('unresolved dates retain source wording and unknown terms do not invent percentages or times',()=>{
  const unknown = 'Réinitialisation le vendredi à 15:30 UTC−7';
  const daysOnly = 'إعادة التعيين بعد يومين';
  const ambiguous = 'Réinitialisation dans 2 heures et 12 périodes';
  for (const text of [unknown,ambiguous,daysOnly])
    assert.deepEqual(usage(['Session actuelle','25 % utilisé',text].join('\n'),observed),[{kind:'session',remainingPercent:75,resetLabel:text}]);
  assert.equal(resetTime('将在 2 小时 7 个自定义周期后重置',observed,'weekly'),null);
  assert.deepEqual(usage('当前会话\n١٢٥٪ 已使用\n三分之一\n每周限额\n仅限 Opus\n٨٠٪',observed),[]);
  assert.equal(usage('الجلسة الحالية\n٩٩٫٥٪ مستخدم',observed)[0].remainingPercent,1);
});
test('ongoing work labels select five distinct props across eleven languages',()=>{
  const cases = [
    ['Planning','Researching','Reading files','Running code','Creating an artifact'],
    ['Erstellt einen Plan','Recherchiert','Liest Dateien','Führt Code aus','Erstellt ein Diagramm'],
    ['正在制定计划','正在研究','正在读取文件','正在执行代码','正在绘制图表'],
    ['योजना बना रहा है','शोध कर रहा है','फ़ाइल पढ़ रहा है','कोड चला रहा है','आरेख बना रहा है'],
    ['Planificando','Investigando','Leyendo archivos','Ejecutando código','Creando un diagrama'],
    ['جارٍ التخطيط','جارٍ البحث عن مصادر','جارٍ قراءة الملف','جارٍ تشغيل الكود','جارٍ إنشاء مخطط'],
    ['Planification en cours','Recherche de sources','Lecture des fichiers','Exécution du code','Création d’un artefact'],
    ['পরিকল্পনা করছে','গবেষণা করছে','ফাইল পড়ছে','কোড চালাচ্ছে','ডায়াগ্রাম তৈরি করছে'],
    ['Planejando','Pesquisando fontes','Lendo arquivos','Executando código','Criando um diagrama'],
    ['Menyusun rencana','Mencari sumber','Membaca file','Menjalankan kode','Membuat diagram'],
    ['منصوبہ بندی جاری ہے','تحقیق جاری ہے','فائل پڑھ رہا ہے','کوڈ چلا رہا ہے','خاکہ بنا رہا ہے']
  ];
  const stop = element('',{'data-testid':'stop-response'});
  const general = element('',{'aria-label':'Thinking'});
  const states = ['planning','searching','reading','executing','drawing'];
  for (const labels of cases) for (const [i, text] of labels.entries()) {
    const row = element('',{'aria-label':text});
    const doc = {querySelectorAll:sel => sel.includes('button') ? [stop] : [general,row]};
    assert.equal(activity(doc), states[i],text);
    doc.querySelectorAll = sel => sel.includes('button') ? [] : [row];
    assert.equal(activity(doc),'idle',text);
  }
  const arbitrary = element('Running code',{'aria-label':'An example about creating an artifact'});
  assert.equal(activity({querySelectorAll:sel=>sel.includes('button')?[stop]:[arbitrary]}),'working');
});
