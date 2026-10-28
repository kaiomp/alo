import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../services/models.dart';
import '../services/social_service.dart';
import '../services/ticks.dart';

/// Everything the demo shows. Times are relative to [now] so "Hoje" and
/// "há 5 min" stay right whenever it runs. All people are fictional.

Uri avatar(String name) => Uri.parse('demo/avatares/$name.jpg');
Uri photo(String name) => Uri.parse('demo/fotos/$name.jpg');

/// The app's name as people see it (one l10n key, `appName`).
final appName = lookupL10n(const Locale('pt')).appName;

/// The demo's made-up server: handles and IDs only, never shown as a real
/// address (profiles show the app's name instead).
const demoHost = 'exemplo.social';

Person _p(String key, String name, String user) =>
    Person(id: '@$key:$demoHost', name: name, handle: '$user@$demoHost', avatar: avatar(key));

final me = _p('bia', 'Bia Santana', 'bia');
final mae = _p('mae', 'Mãe', 'helena.santana');
final pai = _p('joao', 'Pai', 'joao.santana');
final ana = _p('ana', 'Ana Clara', 'anaclara');
final rafael = _p('rafael', 'Rafael Lima', 'rafa');
final juliana = _p('juliana', 'Juliana Ferreira', 'ju.ferreira');
final thiago = _p('thiago', 'Thiago Oliveira', 'thiagoo');
final cida = _p('cida', 'Dona Cida', 'dona.cida');
final carol = _p('carol', 'Carol Souza', 'carolsouza');
final pedro = _p('pedro', 'Pedro Alves', 'pedroalves');
final lucas = _p('lucas', 'Lucas Martins', 'lucasm');
final fernanda = _p('fernanda', 'Fernanda Rocha', 'fe.rocha');
final marcos = _p('marcos', 'Marcos Vinícius', 'marcosv');

/// Photo sizes (width, height) of the files in web/demo/fotos.
const photoSizes = {
  'amazonia': (900, 600),
  'chapada': (900, 557),
  'feira': (900, 600),
  'lencois': (900, 546),
  'moqueca': (900, 675),
  'pao-de-queijo': (900, 675),
  'pordosol': (900, 600),
  'praia-nordeste': (900, 600),
  'praia-rio': (900, 596),
  'recife': (900, 600),
  'salvador': (900, 675),
  'sao-paulo': (900, 600),
  'trabalho': (900, 600),
  'varzea': (900, 600),
};

double ratioOf(String name) {
  final (w, h) = photoSizes[name] ?? (3, 4);
  return w / h;
}

/// One chat of the demo, mutable: scenes add messages and move ticks.
class DemoChat {
  DemoChat({
    required this.id,
    required this.name,
    required this.members,
    required this.messages,
    this.isGroup = false,
    this.avatar,
    this.pinned = false,
    this.muted = false,
    this.unread = 0,
    this.lastSeen,
  });

  final String id;
  final String name;
  final bool isGroup;
  final Uri? avatar;

  /// Everyone but me.
  final List<Person> members;

  /// Newest first, like ChatSession.messages.
  final List<Message> messages;

  /// Message id → photo, for downloads.
  final photos = <String, Uri>{};
  bool pinned;
  bool muted;
  bool favourite = false;
  bool archived = false;
  bool markedUnread = false;
  int unread;
  final DateTime? lastSeen;

  Person get other => members.first;
}

/// Builds the chats. [now] anchors every time.
class DemoWorld {
  DemoWorld(this.now) {
    _build();
  }

  final DateTime now;
  final chats = <DemoChat>[];
  var _n = 0;

  DateTime ago({int d = 0, int h = 0, int m = 0}) => now.subtract(Duration(days: d, hours: h, minutes: m));

  DemoChat chat(String id) => chats.firstWhere((c) => c.id == id);

  String nextId() => 'm${_n++}';

  Message text(Person from, String body, DateTime time, {Tick tick = Tick.read, List<Reaction> reactions = const []}) =>
      Message(
        id: nextId(),
        senderId: from.id,
        senderName: from.name,
        isMine: from == me,
        time: time,
        kind: MessageKind.text,
        body: body,
        tick: from == me ? tick : null,
        reactions: reactions,
      );

  Message image(DemoChat c, Person from, String name, DateTime time, {List<Reaction> reactions = const []}) {
    final (w, h) = photoSizes[name] ?? (720, 1280);
    final m = Message(
      id: nextId(),
      senderId: from.id,
      senderName: from.name,
      isMine: from == me,
      time: time,
      kind: MessageKind.image,
      body: '$name.jpg',
      width: w,
      height: h,
      mimeType: 'image/jpeg',
      tick: from == me ? Tick.read : null,
      reactions: reactions,
    );
    c.photos[m.id] = photo(name);
    return m;
  }

  Message voice(Person from, int seconds, DateTime time, {int seed = 1}) {
    final r = math.Random(seed);
    return Message(
      id: nextId(),
      senderId: from.id,
      senderName: from.name,
      isMine: from == me,
      time: time,
      kind: MessageKind.voice,
      body: 'voz.wav',
      durationMs: seconds * 1000,
      mimeType: 'audio/wav',
      // A speech-like envelope: louder in the middle of each phrase.
      waveform: [
        for (var i = 0; i < 40; i++) (200 + 700 * math.sin(i / 3.2).abs() * (0.5 + r.nextDouble() / 2)).round(),
      ],
      tick: from == me ? Tick.read : null,
    );
  }

  Message file(Person from, String name, int size, DateTime time) => Message(
    id: nextId(),
    senderId: from.id,
    senderName: from.name,
    isMine: from == me,
    time: time,
    kind: MessageKind.file,
    body: name,
    size: size,
    mimeType: 'application/pdf',
    tick: from == me ? Tick.read : null,
  );

  DemoChat _add(DemoChat c, List<Message> Function(DemoChat) oldestFirst) {
    c.messages.addAll(oldestFirst(c).reversed);
    chats.add(c);
    return c;
  }

  void _build() {
    _add(
      DemoChat(id: '!mae', name: mae.name, members: [mae], messages: [], pinned: true, lastSeen: ago(m: 4)),
      (c) => [
        text(mae, 'Bom dia, filha! Dormiu bem?', ago(h: 3, m: 10)),
        text(me, 'Bom dia, mãe! Dormi sim 😊', ago(h: 3, m: 2)),
        text(mae, 'Domingo tem almoço aqui, sua irmã vem também', ago(h: 2, m: 58)),
        text(me, 'Oba! Eu levo a sobremesa', ago(h: 2, m: 40)),
        text(
          mae,
          'Leva um casaquinho que vai esfriar 😘',
          ago(h: 2, m: 39),
          reactions: const [
            Reaction('❤️', 1, mine: true, senders: ['Você']),
          ],
        ),
      ],
    );
    _add(
      DemoChat(
        id: '!familia',
        name: 'Família Santana 💛',
        isGroup: true,
        avatar: avatar('grupo-familia'),
        members: [mae, pai, ana],
        messages: [],
        pinned: true,
        unread: 3,
      ),
      (c) => [
        text(ana, 'Gente, domingo eu levo o bolo de rolo!', ago(h: 1, m: 50)),
        text(mae, 'Que maravilha 😍', ago(h: 1, m: 44)),
        text(me, 'E eu a cocada da padaria da esquina', ago(h: 1, m: 40)),
        image(
          c,
          pai,
          'moqueca',
          ago(m: 52),
          reactions: const [
            Reaction('😍', 2, senders: ['Mãe', 'Ana Clara']),
          ],
        ),
        text(pai, 'Ensaio pro almoço de domingo kkkkk', ago(m: 51)),
        text(ana, 'PAI 😂😂 guarda pra gente', ago(m: 47)),
      ],
    );
    _add(
      DemoChat(id: '!rafael', name: rafael.name, members: [rafael], messages: [], lastSeen: ago(m: 1)),
      (c) => [
        text(rafael, 'Bia, viu a vaga na Mangue Design?', ago(d: 1, h: 3)),
        text(me, 'Vi! Mandei o portfólio ontem à noite 🤞', ago(d: 1, h: 2, m: 55)),
        text(rafael, 'Vai dar bom, teu trabalho é massa demais', ago(d: 1, h: 2, m: 50)),
        text(rafael, 'E aí, fechou o fim de semana em Porto?', ago(m: 24)),
        text(me, 'Fechei! Saio sexta depois do trampo 🚗', ago(m: 22)),
        text(rafael, 'Boa demais', ago(m: 21)),
      ],
    );
    _add(
      DemoChat(
        id: '!pelada',
        name: 'Pelada de quinta ⚽',
        isGroup: true,
        avatar: avatar('grupo-pelada'),
        members: [thiago, pedro, lucas, marcos, rafael],
        messages: [],
        unread: 12,
      ),
      (c) => [
        text(pedro, 'Eu vou!', ago(m: 70)),
        text(lucas, 'Tô dentro', ago(m: 66)),
        text(marcos, 'Levo a bola nova', ago(m: 61)),
        image(c, thiago, 'varzea', ago(m: 40)),
        text(thiago, 'Quem vai hoje? Preciso fechar dois times', ago(m: 38)),
      ],
    );
    _add(
      DemoChat(id: '!juliana', name: juliana.name, members: [juliana], messages: [], unread: 2, lastSeen: ago(m: 9)),
      (c) => [
        text(me, 'Manda foto quando chegar!', ago(d: 1, h: 5)),
        text(juliana, 'Amiga, cheguei em Belém!', ago(m: 58)),
        image(c, juliana, 'amazonia', ago(m: 57)),
        text(juliana, 'O rio daqui é outro mundo 😭', ago(m: 56)),
      ],
    );
    _add(
      DemoChat(id: '!thiago', name: thiago.name, members: [thiago], messages: [], unread: 1, lastSeen: ago(h: 1)),
      (c) => [
        text(me, 'Thiago, me explica de novo o esquema do campeonato?', ago(h: 2, m: 15)),
        voice(thiago, 23, ago(h: 1, m: 30), seed: 3),
      ],
    );
    _add(
      DemoChat(
        id: '!bloco',
        name: 'Bloco da Lua 🌙',
        isGroup: true,
        avatar: avatar('grupo-bloco'),
        members: [carol, fernanda, juliana, ana],
        messages: [],
        muted: true,
        unread: 0,
      )..markedUnread = false,
      (c) => [
        text(fernanda, 'Alguém tem glitter dourado sobrando?', ago(h: 4)),
        text(ana, 'Eu tenho! Levo no ensaio', ago(h: 3, m: 50)),
        text(carol, 'Ensaio sábado às 16h na praça!', ago(h: 3, m: 12)),
      ],
    );
    _add(
      DemoChat(id: '!carol', name: carol.name, members: [carol], messages: [], lastSeen: ago(h: 2)),
      (c) => [
        text(carol, 'Bia, consegue me mandar a proposta hoje?', ago(h: 6)),
        file(me, 'Proposta_identidade_visual.pdf', 2516582, ago(h: 5, m: 20)),
        text(me, 'Tá aí! Qualquer dúvida me alo', ago(h: 5, m: 19)),
        text(carol, 'Recebi! Vou ler com calma e te falo amanhã', ago(h: 4, m: 45)),
      ],
    );
    _add(
      DemoChat(id: '!cida', name: cida.name, members: [cida], messages: [], lastSeen: ago(d: 1)),
      (c) => [
        text(cida, 'Minha filha, chegou uma encomenda sua aqui na portaria 📦', ago(d: 1, h: 6)),
        text(me, 'Obrigada, Dona Cida! Pego mais tarde', ago(d: 1, h: 5, m: 40)),
        text(cida, 'Tá bom. Fiz pão de queijo, passa aqui que tem pra você', ago(d: 1, h: 5, m: 30)),
        text(me, 'Ai que delícia, a senhora é demais 🥰', ago(d: 1, h: 5, m: 28)),
      ],
    );
    _add(
      DemoChat(
        id: '!mangue',
        name: 'Equipe Mangue Design',
        isGroup: true,
        avatar: avatar('grupo-trabalho'),
        members: [fernanda, marcos, pedro],
        messages: [],
      ),
      (c) => [
        text(fernanda, 'Pessoal, apresentação final às 15h, tá?', ago(d: 1, h: 8)),
        text(marcos, 'Fechou. Os mockups estão na pasta', ago(d: 1, h: 7, m: 50)),
        text(me, 'Fechado 👍', ago(d: 1, h: 7, m: 45), tick: Tick.delivered),
      ],
    );
    _add(
      DemoChat(id: '!lucas', name: lucas.name, members: [lucas], messages: [], lastSeen: ago(d: 2)),
      (c) => [
        text(lucas, 'Valeu pela dica do curso de tipografia!', ago(d: 3, h: 2)),
        text(me, 'Imagina! Depois me conta o que achou', ago(d: 3, h: 1)),
      ],
    );
  }
}

/// The feed's "Seguindo" list, newest first.
List<Post> demoFeed(DateTime now) {
  DateTime ago({int h = 0, int m = 0}) => now.subtract(Duration(hours: h, minutes: m));
  Post post(
    String id,
    Person who,
    DateTime t,
    String text, {
    String? img,
    int l = 0,
    int r = 0,
    int s = 0,
    Person? by,
    String? topic,
  }) => Post(
    id: id,
    author: who,
    time: t,
    text: text,
    image: img == null ? null : photo(img),
    imageRatio: img == null ? 1 : ratioOf(img),
    likes: l,
    replies: r,
    reposts: s,
    repostedBy: by,
    topic: topic,
  );
  return [
    post(
      'p1',
      juliana,
      ago(m: 12),
      'Fim de tarde no rio em Belém. Açaí de verdade e ninguém com pressa 💜',
      img: 'amazonia',
      l: 214,
      r: 3,
      s: 9,
    ),
    post(
      'p2',
      pedro,
      ago(m: 34),
      'Lembrete de quinta: algoritmo bom é o que você escolhe e consegue ler. O resto é vitrine.',
      l: 1204,
      r: 2,
      s: 312,
    ),
    post(
      'p3',
      fernanda,
      ago(h: 1, m: 5),
      'Lençóis Maranhenses depois da chuva. Lagoa cheia, céu limpo, silêncio. Que país é esse?',
      img: 'lencois',
      l: 562,
      r: 41,
      s: 77,
    ),
    post(
      'p4',
      cida,
      ago(h: 2),
      'Fiz pão de queijo pra vizinhança toda. Quem passar na portaria pega um 🧀',
      img: 'pao-de-queijo',
      l: 389,
      r: 52,
      s: 12,
      by: rafael,
    ),
    post(
      'p5',
      thiago,
      ago(h: 3),
      'Várzea é patrimônio. Domingo tem final do campeonato da Zona Norte, bora encher a arquibancada ⚽',
      img: 'varzea',
      l: 278,
      r: 33,
      s: 20,
      topic: 'futebol de várzea',
    ),
    post(
      'p6',
      carol,
      ago(h: 4, m: 20),
      'Alguém indica um lugar bom pra comer moqueca em Salvador? Chego sexta!',
      l: 45,
      r: 63,
      s: 2,
    ),
    post(
      'p7',
      marcos,
      ago(h: 5),
      'Pelourinho às 7 da manhã, antes de todo mundo acordar.',
      img: 'salvador',
      l: 731,
      r: 24,
      s: 58,
    ),
    post(
      'p8',
      ana,
      ago(h: 6, m: 30),
      'Recife Antigo num domingo de sol. A saudade começa antes de ir embora.',
      img: 'recife',
      l: 190,
      r: 12,
      s: 6,
    ),
    post(
      'p9',
      lucas,
      ago(h: 8),
      'Primeira semana de estágio e já aprendi que cafezinho é um idioma.',
      l: 88,
      r: 9,
      s: 3,
    ),
    post(
      'p10',
      fernanda,
      ago(h: 10),
      'São Paulo vista de cima tem outro ritmo.',
      img: 'sao-paulo',
      l: 304,
      r: 17,
      s: 11,
    ),
    post(
      'p11',
      me,
      ago(h: 20),
      'Chapada Diamantina me lembrou por que eu desenho: a natureza já resolveu toda a tipografia do mundo.',
      img: 'chapada',
      l: 156,
      r: 14,
      s: 8,
    ),
    post(
      'p12',
      juliana,
      ago(h: 22),
      'Quem mais acha que o Brasil merecia uma rede social que não vende a gente?',
      l: 2310,
      r: 4,
      s: 640,
    ),
  ];
}

/// Replies by post id, oldest first.
Map<String, List<Post>> demoReplies(DateTime now) {
  Post r(String id, Person who, int minutes, String text, {int l = 0}) => Post(
    id: id,
    author: who,
    time: now.subtract(Duration(minutes: minutes)),
    text: text,
    likes: l,
  );
  return {
    'p1': [
      r('r1', ana, 10, 'Que paz 😍 Traz açaí pra mim!', l: 12),
      r('r2', rafael, 8, 'Belém é demais. Vai no Ver-o-Peso cedinho!', l: 8),
      r('r3', mae, 5, 'Cuidado com o sol, menina', l: 21),
    ],
    'p2': [
      r('r4', juliana, 30, 'Gente boa e ordem de chegada. Só isso.', l: 140),
      r('r5', marcos, 25, 'Por isso vim pra cá', l: 96),
    ],
    'p12': [
      r('r6', pedro, 1300, 'Merecia e agora tem', l: 310),
      r('r7', fernanda, 1290, 'E dá pra levar os seguidores se um dia quiser sair. Isso muda tudo.', l: 280),
      r('r8', lucas, 1280, 'Baixei pra família toda', l: 75),
      r('r9', carol, 1270, 'Sem anúncio me seguindo pela internet 🙏', l: 64),
    ],
  };
}

/// Contacts with moments: unseen first.
List<MomentGroup> demoMoments(DateTime now) {
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
  Moment m(String id, String img, int minutes, String caption) =>
      Moment(id: id, image: photo(img), time: ago(minutes), caption: caption);
  return [
    MomentGroup(
      person: juliana,
      moments: [m('s1', 'acai', 95, 'Açaí de respeito em Belém 💜'), m('s2', 'coco', 40, 'Água de coco e mais nada')],
    ),
    MomentGroup(
      person: rafael,
      moments: [
        m('s3', 'carnaval', 70, 'Ensaio do bloco hoje 🥁'),
        m('s4', 'olinda', 30, 'Subindo as ladeiras de Olinda'),
      ],
    ),
    MomentGroup(person: ana, moments: [m('s5', 'ipe', 120, 'O ipê da praça floriu! 💛')]),
    MomentGroup(person: thiago, moments: [m('s6', 'forro', 180, 'São João chegando 🎶')]),
    MomentGroup(person: mae, moments: [m('s7', 'cafe', 240, 'Cafezinho da tarde ☕')]),
    MomentGroup(person: marcos, moments: [m('s8', 'musica', 300, 'Roda de samba no domingo')], seen: true),
    MomentGroup(person: fernanda, moments: [m('s9', 'rio-noite', 420, 'Rio, sempre você')], seen: true),
  ];
}

/// My own posts for the profile grid, newest first (the feed holds p11 too).
List<Post> demoMyPosts(DateTime now) {
  Post p(String id, String img, int hours, String text, int likes) => Post(
    id: id,
    author: me,
    time: now.subtract(Duration(hours: hours)),
    text: text,
    image: photo(img),
    imageRatio: ratioOf(img),
    likes: likes,
  );
  return [
    p('p11', 'chapada', 20, 'Chapada Diamantina me lembrou por que eu desenho.', 156),
    p('b1', 'trabalho', 50, 'Identidade nova saindo do forno ✏️', 98),
    p('b2', 'praia-rio', 80, 'Rio em dia de semana', 210),
    p('b3', 'pordosol', 120, 'Todo pôr do sol é uma paleta pronta', 187),
    p('b4', 'praia-nordeste', 200, 'Maragogi, me espera', 342),
    p('b5', 'olinda', 260, 'Olinda é a melhor referência de cor que existe', 276),
    p('b6', 'cafe', 300, 'Primeiro café, depois kerning', 64),
    p('b7', 'ipe', 400, 'Ipê-amarelo na frente de casa', 421),
    p('b8', 'coco', 520, 'Água de coco é meu combustível', 133),
  ];
}

// ---- "Para você": creators, local businesses and one ad (all fictional) ----

Uri video(String name) => Uri.parse('demo/videos/$name.mp4');
Uri poster(String name) => Uri.parse('demo/videos/$name.jpg');

Person _creator(String key, String name, {Uri? avatar, String? business}) =>
    Person(id: '@$key:$demoHost', name: name, handle: '$key@$demoHost', avatar: avatar, business: business);

final iara = _creator('iara.surf', 'Iara Mendes');
final bento = _creator('mestrebento', 'Mestre Bento');
final cozinhaDaRua = _creator('cozinhadarua', 'Cozinha da Rua');
final recifeAPe = _creator('recifeape', 'Recife a Pé');
final ribeirinho = _creator('ribeirinho', 'Ribeirinho Filmes');
final coletivo = _creator('coletivo.mangue', 'Coletivo Mangue Arte');
final cordel = _creator('cordelvivo', 'Ateliê Cordel Vivo');
final cafeBaoba = _creator('cafebaoba', 'Café Baobá', avatar: photo('cafe'), business: 'Café · Boa Vista, Recife');
final donaZefa = _creator(
  'barracadazefa',
  'Barraca da Dona Zefa',
  avatar: photo('feira'),
  business: 'Frutas e verduras · Feira de Casa Amarela',
);
final varzeaWear = _creator('varzeawear', 'Várzea Wear', business: 'Uniformes esportivos · Recife');
final livrariaMare = _creator('livrariamare', 'Livraria Maré', business: 'Livraria · Recife Antigo');

const topicsAll = ['praia', 'futebol de várzea', 'comida', 'arte', 'música e capoeira', 'natureza', 'cidade'];

/// Posts that "Perto de você" keeps (Recife and around).
const nearIds = {'r-surf', 'r-futebol', 'collab', 'r-capoeira', 'cafe-text', 'olinda', 'r-rua', 'r-feira', 'cordel'};

/// "Para você" in the default order, before the ad goes in.
List<Post> demoForYou(DateTime now, List<Post> following) {
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
  Post friend(String id, Reason reason, String topic) =>
      following.firstWhere((p) => p.id == id).copyWith(reason: reason, topic: topic);
  Reason follows(Person p) => Reason(ReasonKind.follows, p.at);
  Post reel(
    String id,
    Person who,
    int minutes,
    String file,
    String text,
    Reason reason,
    String topic, {
    int l = 0,
    int r = 0,
    Person? partner,
  }) => Post(
    id: id,
    author: who,
    time: ago(minutes),
    text: text,
    video: video(file),
    image: poster(file),
    imageRatio: 9 / 16,
    likes: l,
    replies: r,
    reason: reason,
    topic: topic,
    paidPartner: partner,
  );
  const popular = Reason(ReasonKind.popular, 'Recife');
  return [
    friend('p1', follows(juliana), 'natureza'),
    friend('p2', follows(pedro), 'cidade'),
    reel('r-surf', iara, 25, 'praia-surf', 'Maré boa hoje cedo. Quem vem amanhã? 🌊', popular, 'praia', l: 3120, r: 88),
    reel(
      'r-futebol',
      thiago,
      40,
      'futebol',
      'Uniforme novo pro time da quebrada 🙌 Domingo tem final!',
      follows(thiago),
      'futebol de várzea',
      l: 641,
      r: 57,
      partner: varzeaWear,
    ),
    Post(
      id: 'collab',
      author: cafeBaoba,
      coAuthor: donaZefa,
      time: ago(55),
      text: 'Café coado de Garanhuns + tapioca da feira: só neste sábado, na barraca da Dona Zefa ☕',
      image: photo('cafe'),
      imageRatio: 0.8,
      likes: 402,
      replies: 31,
      reason: const Reason(ReasonKind.near, 'Boa Vista'),
      topic: 'comida',
    ),
    reel(
      'r-comida',
      cozinhaDaRua,
      70,
      'comida-de-rua',
      'Milho cozido na esquina: o lanche mais honesto do Brasil 🌽',
      const Reason(ReasonKind.topic, 'comida'),
      'comida',
      l: 1880,
      r: 140,
    ),
    friend('p3', follows(fernanda), 'natureza'),
    reel(
      'r-capoeira',
      bento,
      90,
      'capoeira',
      'Roda de sábado na praça. Chega mais, ninguém fica de fora.',
      popular,
      'música e capoeira',
      l: 2240,
      r: 96,
    ),
    Post(
      id: 'cafe-text',
      author: cafeBaoba,
      time: ago(110),
      text: 'Bolo de rolo saindo do forno agora. Café coado até as 20h, aqui na Boa Vista.',
      likes: 87,
      replies: 6,
      reason: const Reason(ReasonKind.near, 'Boa Vista'),
      topic: 'comida',
    ),
    Post(
      id: 'olinda',
      author: coletivo,
      time: ago(130),
      text: 'Muro novo no Amparo, em Olinda. Tinta, vizinhança e três dias de mutirão.',
      image: photo('olinda'),
      imageRatio: 0.8,
      likes: 958,
      replies: 44,
      reason: const Reason(ReasonKind.topic, 'arte'),
      topic: 'arte',
    ),
    reel(
      'r-rua',
      recifeAPe,
      150,
      'rua-cidade',
      'Sábado de manhã no centro. Barulho bom.',
      popular,
      'cidade',
      l: 1310,
      r: 52,
    ),
    reel(
      'r-feira',
      donaZefa,
      170,
      'feira',
      'Chegou manga, caju e pitomba! Até meio-dia na feira de Casa Amarela.',
      const Reason(ReasonKind.near, 'Casa Amarela'),
      'comida',
      l: 276,
      r: 19,
    ),
    Post(
      id: 'cordel',
      author: cordel,
      time: ago(200),
      text: 'Oficina de xilogravura aberta ao público, domingo, no mercado da Boa Vista. Traga papel e vontade.',
      likes: 312,
      replies: 27,
      reason: const Reason(ReasonKind.topic, 'arte'),
      topic: 'arte',
    ),
    reel(
      'r-rio',
      ribeirinho,
      240,
      'rio-amazonia',
      'Amanhecer no rio. Nenhuma notificação chega aqui.',
      const Reason(ReasonKind.topic, 'natureza'),
      'natureza',
      l: 4410,
      r: 120,
    ),
    friend('p12', follows(juliana), 'cidade'),
  ];
}

/// The one ad of the demo: clearly a sponsored post, chosen by topic only.
List<Post> demoAds(DateTime now) => [
  Post(
    id: 'ad-livraria',
    author: livrariaMare,
    time: now.subtract(const Duration(hours: 5)),
    text: 'Sarau de violão e livros independentes. Sábado, 16h, no Recife Antigo. Entrada franca.',
    image: photo('musica'),
    imageRatio: 0.8,
    likes: 129,
    sponsored: true,
    topic: 'arte',
  ),
];

final demoAlgorithms = [
  FeedChoice(
    id: 'padrao',
    name: 'Padrão $appName',
    about: 'Quem você segue, perto de você e temas de que gosta, em equilíbrio.',
  ),
  FeedChoice(id: 'perto', name: 'Perto de você', about: 'O que acontece em Recife e arredores.'),
  FeedChoice(id: 'seguindo', name: 'Só quem eu sigo', about: 'Sem recomendações: igual à aba Seguindo.'),
  FeedChoice(
    id: 'arte-pe',
    name: 'Só arte de Pernambuco',
    about: 'Arte, música e capoeira feitas aqui.',
    by: 'coletivo.mangue',
    users: 12400,
  ),
  FeedChoice(
    id: 'varzea',
    name: 'Várzea de todo o Brasil',
    about: 'Futebol de bairro, de Norte a Sul.',
    by: 'ligadavarzea',
    users: 8350,
  ),
];

/// Profile bios for the people and businesses of "Para você".
final demoBios = {
  cafeBaoba.id: 'Café coado, bolo de rolo e mesa na calçada. Seg a sáb, 7h às 20h, na Boa Vista.',
  donaZefa.id: 'Frutas da estação há 31 anos na feira de Casa Amarela. Sábado e domingo até meio-dia.',
  varzeaWear.id: 'Uniforme para time de bairro, feito em Recife.',
  livrariaMare.id: 'Livros independentes e saraus no Recife Antigo.',
  iara.id: 'Surfe, mar e Boa Viagem cedinho.',
  bento.id: 'Capoeira Angola desde 1989. Roda aberta aos sábados.',
  cozinhaDaRua.id: 'A comida de rua do Brasil, uma esquina por vez.',
  recifeAPe.id: 'Recife a pé, sem pressa.',
  ribeirinho.id: 'Filmes curtos sobre a vida nos rios.',
  coletivo.id: 'Arte de rua, mutirão e muro bonito.',
  cordel.id: 'Xilogravura e cordel com a vizinhança.',
};
