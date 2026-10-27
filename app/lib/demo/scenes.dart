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
const _moments = 1, _square = 2, _voice = 3, _profile = 4;

/// Steps before t = 0, under the cover (for example: open the right tab).
typedef SetUp = Future<void> Function(Director d);

final L10n _l = lookupL10n(const Locale('pt'));
const _width = 412.0;

final scenes = <String, (SetUp?, Scene)>{
  'conversa': (null, _conversa),
  'momentos': ((d) => d.tap(d.tab(_moments)), _momentosScene),
  'praca': ((d) => d.tap(d.tab(_square)), _praca),
  'voz': ((d) => d.tap(d.tab(_voice)), _voz),
  'dados': ((d) => d.tap(d.tab(_profile)), _dados),
  'calma': ((d) => d.tap(d.tab(_square)), _calma),
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

Future<void> _praca(Director d, DemoKit kit) async {
  await d.at(1, 'toca em "sem algoritmo"');
  await d.tap(d.key('chronological'));
  await d.at(3, 'curte');
  await d.tap(d.key('like_p1'));
  await d.at(4.2, 'abre a publicação');
  await d.tap(d.key('post_p1'), at: const Offset(0.5, 0.06));
  await d.at(5.2, 'responde');
  await d.tap(d.key('reply_field'));
  await d.typeText('Leva a gente na próxima! 💜');
  await d.at(7.4, 'envia a resposta');
  await d.tap(d.key('reply_send'));
  await d.at(8.8, 'volta');
  await d.tap(d.type<BackButton>());
  await d.at(9.8, 'rola');
  await d.reveal('post_image_p3');
  await d.at(12, 'toque duplo na foto');
  await d.doubleTap(d.key('post_image_p3'));
  await d.at(13.4, 'rola');
  await d.reveal('repost_p5', alignment: 0.75, duration: const Duration(milliseconds: 1200));
  await d.at(15, 'reposta');
  await d.tap(d.key('repost_p5'));
  await d.at(16.4, 'volta ao topo');
  await d.scrollTo('feed', 0, duration: const Duration(milliseconds: 1100));
  await d.at(17.8, 'escreve');
  await d.tap(d.key('compose'));
  await d.at(18.6);
  await d.typeText(
    'Feira de Casa Amarela hoje cedo: manga a 5 reais e prosa boa de graça 🥭',
    perChar: const Duration(milliseconds: 38),
  );
  await d.at(21.8, 'anexa foto');
  await d.tap(d.key('compose_photo'));
  await d.at(23.4, 'publica');
  await d.tap(d.key('publish'));
  await d.at(25, 'rola até o fim: "Você está em dia"');
  await d.scrollToEnd('feed', duration: const Duration(milliseconds: 2400));
  await d.hold(29.4);
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
  await d.typeText('bia@praca.exemplo.social', perChar: const Duration(milliseconds: 60));
  await d.at(12.5, 'muda de servidor');
  await d.tap(d.key('move_start'));
  await d.at(19.5, 'conclui');
  await d.tap(d.text(_l.done));
  await d.at(20.6, 'rola as publicações');
  await d.scrollTo('profile', 320, duration: const Duration(milliseconds: 1400));
  await d.hold(24);
}

Future<void> _voz(Director d, DemoKit kit) async {
  await d.at(1, 'abre a ficha de Helena Barros');
  await d.tap(d.key('rep_helena'));
  await d.at(2, 'presença e gastos, com fonte');
  await d.scrollTo('rep_page', 360, duration: const Duration(milliseconds: 1500));
  await d.at(4.2, 'como votou');
  await d.scrollTo('rep_page', 760, duration: const Duration(milliseconds: 1200));
  await d.at(6.4, 'volta');
  await d.tap(d.type<BackButton>());
  await _vote(d, 7.3);
  await d.at(15.6, 'resultado por estado');
  await d.reveal('by_state', alignment: 0.15, duration: const Duration(milliseconds: 1200));
  await d.at(17.6, 'volta');
  await d.tap(d.type<BackButton>());
  await _sign(d, 18.4);
  await d.at(22.6, 'Mobilize');
  await d.tap(d.key('voz_section_3'));
  await d.at(23.6, 'entra num canal');
  await d.tap(d.key('join_passe'));
  await d.hold(26.6);
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
  await d.at(1, 'rola a Praça até o fim');
  await d.scrollToEnd('feed', duration: const Duration(milliseconds: 2800));
  await d.at(5.3, 'Perfil');
  await d.tap(d.tab(_profile));
  await _limit(d, 6.3);
  await d.at(10, 'liga o Modo descanso');
  await d.tap(d.key('rest_mode'));
  await d.at(11.2);
  await d.reveal('grey_mode', alignment: 0.8, duration: const Duration(milliseconds: 900));
  await d.at(12.6, 'esconde as curtidas');
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
  // Praça
  await d.at(28, 'aba Praça');
  await d.tap(d.tab(_square));
  await d.at(29, 'toca em "sem algoritmo"');
  await d.tap(d.key('chronological'));
  await d.at(31, 'rola');
  await d.reveal('post_image_p3');
  await d.at(33.2, 'toque duplo na foto');
  await d.doubleTap(d.key('post_image_p3'));
  await d.at(34.6, 'volta ao topo');
  await d.scrollTo('feed', 0, duration: const Duration(milliseconds: 1000));
  await d.at(36, 'escreve');
  await d.tap(d.key('compose'));
  await d.at(36.8);
  await d.typeText('Conversa, momentos e praça num lugar só. E é nosso 💜', perChar: const Duration(milliseconds: 40));
  await d.at(39.6, 'publica');
  await d.tap(d.key('publish'));
  // Voz
  await d.at(42, 'aba Voz');
  await d.tap(d.tab(_voice));
  await _vote(d, 43);
  await d.at(51, 'volta');
  await d.tap(d.type<BackButton>());
  await _sign(d, 52);
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
  await d.typeText('bia@praca.exemplo.social', perChar: const Duration(milliseconds: 55));
  await d.at(67.6, 'muda de servidor');
  await d.tap(d.key('move_start'));
  await d.at(73.2, 'conclui');
  await d.tap(d.text(_l.done));
  // Bem-estar
  await _limit(d, 74.5);
  await d.at(78, '"Hora de uma pausa"');
  kit.wellbeing.elapse(1);
  await d.at(80.5, 'mais 5 minutos');
  await d.tap(d.key('pause_more'));
  await d.at(81.5, 'volta');
  await d.tap(d.type<BackButton>());
  await d.at(82.5, 'volta para Conversas');
  await d.tap(d.tab(0));
  await d.hold(84.5);
}
