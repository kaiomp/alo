import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'demo_chat.dart';
import 'demo_data.dart';
import 'demo_wellbeing.dart';
import 'director.dart';

/// The self-playing scenes, by URL name (`?cena=conversa`). Times are
/// seconds from the scene's first frame; pitch/cenas.md lists the same
/// beats for the video captions. Every scene holds still 1 s at the start
/// and 2 s at the end.
typedef Scene = Future<void> Function(Director d, DemoKit kit);

/// The demo services a scene drives directly (messages arriving, time
/// passing).
class DemoKit {
  const DemoKit({required this.chat, required this.wellbeing});
  final DemoChatService chat;
  final DemoWellbeing wellbeing;
}

/// Bottom bar order in the demo.
const _moments = 1, _feed = 2, _voice = 3, _profile = 4;

/// The feed tab's name (one l10n key, `tabFeed`), for the beat log.
final _feedName = _l.tabFeed;

/// A tap on the dimmed area above a bottom sheet closes it.
const _aboveSheet = Rect.fromLTWH(180, 110, 50, 20);

/// Steps before t = 0, under the cover (for example: open the right tab).
typedef SetUp = Future<void> Function(Director d);

final L10n _l = lookupL10n(const Locale('pt'));
const _width = 412.0;

final scenes = <String, (SetUp?, Scene)>{
  'conversa': (null, _conversa),
  'momentos': ((d) => d.tap(d.tab(_moments)), _momentosScene),
  'rede': ((d) => d.tap(d.tab(_feed)), _rede),
  // The scene's first name; same scene.
  'praca': ((d) => d.tap(d.tab(_feed)), _rede),
  'simples': (null, _simples),
  'algoritmo': ((d) => d.tap(d.tab(_feed)), _algoritmo),
  'voz': ((d) => d.tap(d.tab(_voice)), _voz),
  'dados': ((d) => d.tap(d.tab(_profile)), _dados),
  'calma': ((d) => d.tap(d.tab(_feed)), _calma),
  'tour': (null, _tour),
};

Future<void> _send(Director d, String text, double at) async {
  await d.at(at, 'digita "$text"');
  await d.tap(d.key('composer_text'));
  await d.typeText(text);
}

Future<void> _conversa(Director d, DemoKit kit) async {
  final chat = kit.chat;
  const id = '!rafael';
  await d.at(1, 'abre a conversa com Rafael');
  await d.tap(d.key('chat_Rafael Lima'));
  await d.at(2.2, 'toca no aviso de criptografia');
  await d.tap(d.key('e2e_notice'));
  await d.at(5, 'fecha a explicação');
  await d.tap(d.text(_l.gotIt));
  await d.at(5.6, 'Rafael digitando');
  chat.setTyping(id, rafael, true);
  await d.at(7, 'chega mensagem');
  chat.receive(id, chat.world.text(rafael, 'Olha o que tá te esperando 😍', DateTime.now()));
  await d.at(8, 'chega foto');
  chat.setTyping(id, rafael, false);
  final photo = chat.receivePhoto(id, rafael, 'praia-nordeste');
  await _send(d, 'Que lindo!! Já tô contando as horas', 9.6);
  await d.at(12.3, 'envia: relógio, ✓, ✓✓, azul em 14,5 s');
  await d.tap(d.key('send'));
  await d.at(15, 'Rafael gravando');
  chat.setTyping(id, rafael, true);
  await d.at(17, 'chega áudio');
  chat.setTyping(id, rafael, false);
  chat.receive(id, chat.world.voice(rafael, 12, DateTime.now(), seed: 7));
  await d.at(18.2, 'segura a foto');
  await d.longPress(d.key('msg_${photo.id}'));
  await d.at(19.4, 'reage com ❤️');
  await d.tap(d.key('react_❤️'));
  await _send(d, 'Kkkk vou levar o protetor 😎', 20.5);
  await d.at(23, 'envia');
  await d.tap(d.key('send'));
  await d.at(25.5, 'Rafael digitando');
  chat.setTyping(id, rafael, true);
  await d.at(26.6, 'chega resposta');
  chat.setTyping(id, rafael, false);
  chat.receive(id, chat.world.text(rafael, 'Vai ser massa demais 🌊', DateTime.now()));
  d.unfocus();
  await d.hold(28.6);
}

Future<void> _story(Director d, double at, {required bool reply}) async {
  await d.at(at, 'abre o momento de Juliana');
  await d.tap(d.key('ring_${juliana.id}'));
  await d.at(at + 3.2, 'toca para o próximo');
  await d.tap(const Rect.fromLTWH(_width * 0.7, 300, _width * 0.25, 300));
  await d.at(at + 6, 'desliza para Rafael');
  await d.drag(const Offset(_width * 0.85, 450), const Offset(-_width * 0.7, 0));
  if (!reply) return;
  await d.at(at + 8, 'responde');
  await d.tap(d.key('moment_reply'));
  await d.typeText('Que energia!! Sábado tô lá 🥁');
  await d.at(at + 10.5, 'envia a resposta');
  await d.tap(d.key('moment_send'));
}

Future<void> _momentosScene(Director d, DemoKit kit) async {
  await _story(d, 1, reply: true);
  await d.at(13.5, 'próximo momento de Rafael');
  await d.tap(const Rect.fromLTWH(_width * 0.7, 300, _width * 0.25, 300));
  await d.at(20.5, 'desliza para baixo e fecha');
  await d.drag(const Offset(_width / 2, 380), const Offset(0, 320), duration: const Duration(milliseconds: 420));
  await d.hold(23.5);
}

Future<void> _rede(Director d, DemoKit kit) async {
  await d.at(1, '$_feedName · Para você: rola até o vídeo de surfe');
  await d.reveal('post_r-surf', alignment: 0.12, duration: const Duration(milliseconds: 1600));
  await d.at(4.8, 'reel de futebol, "Parceria paga com @varzeawear"');
  await d.reveal('post_r-futebol', alignment: 0.1, duration: const Duration(milliseconds: 1200));
  await d.at(7.8, 'post "Patrocinado"');
  await d.reveal('post_ad-livraria', alignment: 0.12, duration: const Duration(milliseconds: 1200));
  await d.at(9.4, '"Por que este anúncio?"');
  await d.tap(d.key('why_ad_ad-livraria'));
  await d.at(12, 'fecha');
  await d.tap(d.key('ad_sheet_close'));
  await d.at(12.6, 'post em parceria: Café Baobá e Barraca da Dona Zefa');
  await d.reveal('post_collab', alignment: 0.12, duration: const Duration(milliseconds: 1000));
  await d.at(14, '"Por que estou vendo isto?"');
  await d.tap(d.key('why_collab'));
  await d.at(16.2, 'fecha');
  await d.tap(_aboveSheet);
  await d.at(17, 'rola até o reel de comida de rua');
  await d.reveal('post_r-comida', alignment: 0.1, duration: const Duration(milliseconds: 1000));
  await d.at(18.6, 'abre o reel em tela cheia');
  await d.tap(d.key('reel_r-comida'));
  await d.at(20.8, 'desliza para o próximo');
  await d.drag(const Offset(_width / 2, 700), const Offset(0, -460), duration: const Duration(milliseconds: 380));
  await d.at(23, 'fecha');
  await d.tap(d.key('reel_close'));
  await d.at(23.8, 'aba Seguindo');
  await d.tap(d.key('tab_following'));
  await d.at(24.6, 'rola até "Você está em dia"');
  await d.scrollToEnd('feed', duration: const Duration(milliseconds: 2200));
  await d.hold(28.8);
}

Future<void> _algoritmo(Director d, DemoKit kit) async {
  await d.at(1, 'abre "Escolha seu algoritmo"');
  await d.tap(d.key('choose_algorithm'));
  await d.at(2.6, 'escolhe "Só arte de Pernambuco"');
  await d.tap(d.key('algorithm_arte-pe'));
  await d.at(4, 'rola até os temas');
  await d.reveal('topic_música e capoeira', alignment: 0.6, duration: const Duration(milliseconds: 1000));
  await d.at(5.6, 'desliga o tema "música e capoeira"');
  await d.tap(d.key('topic_música e capoeira'));
  await d.at(7, 'volta: o feed mudou');
  await d.tap(d.type<BackButton>());
  await d.at(10, '"Por que estou vendo isto?"');
  await d.tap(d.key('why_olinda'));
  await d.at(12.5, 'fecha');
  await d.tap(_aboveSheet);
  await d.at(13.4, 'volta ao Padrão $appName');
  await d.tap(d.key('choose_algorithm'));
  await d.at(14.6);
  await d.tap(d.key('algorithm_padrao'));
  await d.at(15.6);
  await d.tap(d.type<BackButton>());
  await d.hold(18.6);
}

Future<void> _dados(Director d, DemoKit kit) async {
  await d.at(1.2, 'toca em Exportar tudo');
  await d.tap(d.key('export_all'));
  await d.at(3, 'exporta');
  await d.tap(d.key('export_start'));
  await d.at(8, 'salva e fecha');
  await d.tap(d.key('export_close'));
  await d.at(9.2, 'toca em Levar seguidores');
  await d.tap(d.key('move_followers'));
  await d.at(10.2, 'digita o novo endereço');
  await d.tap(d.key('move_address'));
  await d.typeText('bia@rede.exemplo.social', perChar: const Duration(milliseconds: 60));
  await d.at(12.5, 'muda de servidor');
  await d.tap(d.key('move_start'));
  await d.at(19.5, 'conclui');
  await d.tap(d.text(_l.done));
  await d.at(20.6, 'rola as publicações');
  await d.scrollTo('profile', 320, duration: const Duration(milliseconds: 1400));
  await d.hold(24);
}

Future<void> _voz(Director d, DemoKit kit) async {
  await d.at(1, 'Pernambuco');
  await d.tap(d.key('level_state'));
  await d.at(2.4, 'Recife');
  await d.tap(d.key('level_city'));
  await d.at(3.8, 'Casa Amarela: problemas do bairro');
  await d.tap(d.key('level_neighbourhood'));
  await d.at(5.4, 'apoia o buraco da Rua Padre Lemos');
  await d.tap(d.key('support_buraco'));
  await d.at(6.6, 'Vote');
  await d.tap(d.key('voz_section_1'));
  await d.at(7.4, 'abre "Nova praça ou posto de saúde 24h?"');
  await d.tap(d.key('consulta_b1'));
  await d.at(8.4, 'verifica: morador de Casa Amarela');
  await d.tap(d.key('verify'));
  await d.at(10.4, 'escolhe "Posto de saúde 24h"');
  await d.tap(d.key('option_1'));
  await d.at(11.2, 'confirma: Casa Amarela: 1.240 votos');
  await d.tap(d.key('confirm_vote'));
  await d.at(13.6, 'volta');
  await d.tap(d.type<BackButton>());
  await d.at(14.4, 'Brasil');
  await d.tap(d.key('level_country'));
  await d.at(15.4, 'abre o PL 2841/2026');
  await d.tap(d.key('consulta_c1'));
  await d.at(16.6, 'Sim');
  await d.tap(d.key('choice_yes'));
  await d.at(17.4, 'confirma: o povo 78% x a Câmara 41%');
  await d.tap(d.key('confirm_vote'));
  await d.at(20.6, 'volta');
  await d.tap(d.type<BackButton>());
  await _sign(d, 21.4);
  await d.hold(27);
}

/// Vote → open the consultation, verify, vote yes, see people vs Chamber.
Future<void> _vote(Director d, double at) async {
  await d.at(at, 'Vote');
  await d.tap(d.key('voz_section_1'));
  await d.at(at + 1, 'abre a consulta do PL 2841/2026');
  await d.tap(d.key('consulta_c1'));
  await d.at(at + 2.1, 'verifica a identidade (selo em +1,4 s)');
  await d.tap(d.key('verify'));
  await d.at(at + 4.3, 'escolhe Sim');
  await d.tap(d.key('choice_yes'));
  await d.at(at + 5.1, 'confirma: o povo 78% x a Câmara 41%');
  await d.tap(d.key('confirm_vote'));
}

/// Proponha → sign the school-meals petition; it crosses the threshold.
Future<void> _sign(Director d, double at) async {
  await d.at(at, 'Proponha');
  await d.tap(d.key('voz_section_2'));
  await d.at(at + 1, 'assina: a barra enche até a meta');
  await d.tap(d.key('sign_merenda'));
}

Future<void> _calma(Director d, DemoKit kit) async {
  await d.at(1, 'aba Seguindo');
  await d.tap(d.key('tab_following'));
  await d.at(1.6, 'rola até "Você está em dia"');
  await d.scrollToEnd('feed', duration: const Duration(milliseconds: 2400));
  await d.at(5.3, 'Perfil');
  await d.tap(d.tab(_profile));
  await _limit(d, 6.3);
  await d.at(10, 'liga o Modo descanso');
  await d.tap(d.key('rest_mode'));
  await d.at(11);
  await d.reveal('grey_mode', alignment: 0.8, duration: const Duration(milliseconds: 900));
  await d.at(12, 'desliga a reprodução automática de vídeos');
  await d.tap(d.key('autoplay'));
  await d.at(12.8, 'esconde as curtidas');
  await d.tap(d.key('hide_likes'));
  await d.at(13.6, 'modo cinza');
  await d.tap(d.key('grey_mode'));
  await d.at(15.6, 'cores de volta');
  await d.tap(d.key('grey_mode'));
  await d.at(17, 'chega ao limite: "Hora de uma pausa"');
  kit.wellbeing.elapse(1);
  await d.hold(21.5);
}

/// Opens Bem-estar from Perfil and brings the limit from 45 to 25 min.
Future<void> _limit(Director d, double at) async {
  await d.at(at, 'abre Bem-estar');
  await d.tap(d.key('wellbeing_entry'));
  await d.at(at + 1.3, 'limite: 45 → 25 min');
  for (var i = 0; i < 4; i++) {
    await d.at(at + 1.3 + i * 0.5);
    await d.tap(d.key('limit_less'));
  }
}

Future<void> _tour(Director d, DemoKit kit) async {
  final chat = kit.chat;
  // Conversas
  await d.at(1, 'abre o grupo da família');
  await d.tap(d.key('chat_Família Santana 💛'));
  await d.at(4, 'volta');
  await d.tap(d.type<BackButton>());
  await d.at(5, 'abre a conversa com Rafael');
  await d.tap(d.key('chat_Rafael Lima'));
  await d.at(6);
  chat.setTyping('!rafael', rafael, true);
  await d.at(7.2, 'chega mensagem');
  chat.setTyping('!rafael', rafael, false);
  chat.receive('!rafael', chat.world.text(rafael, 'Bia, já viu os momentos de hoje? 👀', DateTime.now()));
  await _send(d, 'Vou ver agora!', 8);
  await d.at(9.4, 'envia');
  await d.tap(d.key('send'));
  await d.at(12, 'volta');
  d.unfocus();
  await d.tap(d.type<BackButton>());
  // Momentos
  await d.at(13, 'aba Momentos');
  await d.tap(d.tab(_moments));
  await _story(d, 14.2, reply: true);
  await d.at(26.5, 'fecha');
  await d.tap(d.key('moment_close'));
  // Feed
  await d.at(28, 'aba $_feedName · Para você');
  await d.tap(d.tab(_feed));
  await d.at(29, 'rola: reel de surfe tocando');
  await d.reveal('post_r-surf', alignment: 0.12, duration: const Duration(milliseconds: 1400));
  await d.at(31, 'reel com "Parceria paga"');
  await d.reveal('post_r-futebol', alignment: 0.1, duration: const Duration(milliseconds: 900));
  await d.at(32.2, 'post "Patrocinado"');
  await d.reveal('post_ad-livraria', alignment: 0.12, duration: const Duration(milliseconds: 1000));
  await d.at(33.6, '"Por que este anúncio?"');
  await d.tap(d.key('why_ad_ad-livraria'));
  await d.at(35.4, 'fecha');
  await d.tap(d.key('ad_sheet_close'));
  await d.at(36, 'escreve');
  await d.tap(d.key('compose'));
  await d.at(36.8);
  await d.typeText('Conversa, momentos e vídeos num lugar só. E é nosso 💜', perChar: const Duration(milliseconds: 40));
  await d.at(39.4, 'publica');
  await d.tap(d.key('publish'));
  await d.at(40.4, 'aba Seguindo: o post novo no topo');
  await d.tap(d.key('tab_following'));
  // Voz
  await d.at(42, 'aba Voz');
  await d.tap(d.tab(_voice));
  await _vote(d, 43);
  await d.at(51, 'volta');
  await d.tap(d.type<BackButton>());
  await d.at(52, 'Acompanhe');
  await d.tap(d.key('voz_section_0'));
  await d.at(52.8, 'Casa Amarela: problemas do bairro');
  await d.tap(d.key('level_neighbourhood'));
  await d.at(54.2, 'apoia');
  await d.tap(d.key('support_buraco'));
  // Perfil
  await d.at(57, 'aba Perfil');
  await d.tap(d.tab(_profile));
  await d.at(58.2, 'exportar tudo');
  await d.tap(d.key('export_all'));
  await d.at(59.6, 'exporta');
  await d.tap(d.key('export_start'));
  await d.at(64, 'fecha');
  await d.tap(d.key('export_close'));
  await d.at(65, 'levar seguidores');
  await d.tap(d.key('move_followers'));
  await d.at(66);
  await d.tap(d.key('move_address'));
  await d.typeText('bia@rede.exemplo.social', perChar: const Duration(milliseconds: 55));
  await d.at(67.6, 'muda de servidor');
  await d.tap(d.key('move_start'));
  await d.at(73.2, 'conclui');
  await d.tap(d.text(_l.done));
  // Bem-estar
  await _limit(d, 74.5);
  await d.at(78, '"Hora de uma pausa"');
  kit.wellbeing.elapse(1);
  await d.at(80, 'mais 5 minutos');
  await d.tap(d.key('pause_more'));
  await d.at(80.8, 'volta');
  await d.tap(d.type<BackButton>());
  // Modo simples
  await d.at(81.6, 'Configurações');
  await d.tap(d.key('settings'));
  await d.at(82.6, 'liga o Modo simples');
  await d.tap(d.key('simple_switch'));
  await d.at(84.6, 'desliga');
  await d.tap(d.key('simple_switch'));
  await d.at(85.6, 'volta');
  await d.tap(d.type<BackButton>());
  await d.at(86.4, 'volta para Conversas');
  await d.tap(d.tab(0));
  await d.hold(88.4);
}

/// First launch: the Modo simples question, then a voice message to Mãe.
Future<void> _simples(Director d, DemoKit kit) async {
  final chat = kit.chat;
  await d.at(1.5, '"Sim, quero": letras maiores, três abas');
  await d.tap(d.key('simple_yes'));
  await d.at(3.5, 'abre a conversa com a Mãe');
  await d.tap(d.key('chat_Mãe'));
  await d.at(5, 'toca no microfone: gravando');
  await d.tap(d.key('mic'));
  await d.at(7.5, 'envia o áudio');
  await d.tap(d.key('send_voice'));
  await d.at(9.6, 'Mãe digitando');
  chat.setTyping('!mae', mae, true);
  await d.at(11, 'Mãe responde');
  chat.setTyping('!mae', mae, false);
  chat.receive('!mae', chat.world.text(mae, 'Que bom ouvir sua voz, filha 💛', DateTime.now()));
  await d.hold(14);
}
