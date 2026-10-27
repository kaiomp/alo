import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/civic_service.dart';

/// Voz on invented data. Every politician, bill and number here is
/// fictional; the screens say "Dados de exemplo".
class DemoCivic implements CivicService {
  DemoCivic(DateTime now)
    : _consultas = ValueNotifier([
        Consulta(
          id: 'c1',
          bill: 'PL 2841/2026',
          title: 'Passe livre para estudantes',
          summary: 'Transporte público gratuito para estudantes de escolas e universidades públicas em todo o país, pago por um fundo federal.',
          closes: now.add(const Duration(days: 34)),
          yes: 1284310,
          no: 298120,
          abstain: 64900,
          chamberYes: 210,
          byState: const {
            'AM': 0.81,
            'BA': 0.82,
            'DF': 0.66,
            'MG': 0.77,
            'PE': 0.84,
            'PR': 0.71,
            'RS': 0.69,
            'SP': 0.74,
          },
        ),
        Consulta(
          id: 'c2',
          bill: 'PL 1907/2026',
          title: 'Transparência nas emendas',
          summary: 'Toda emenda parlamentar publicada na internet em até 48 horas, com autor, valor e destino.',
          closes: now.add(const Duration(days: 12)),
          yes: 2104552,
          no: 91230,
          abstain: 40100,
          byState: const {
            'AM': 0.93,
            'BA': 0.94,
            'DF': 0.95,
            'MG': 0.94,
            'PE': 0.95,
            'PR': 0.93,
            'RS': 0.94,
            'SP': 0.94,
          },
        ),
        Consulta(
          id: 'c3',
          bill: 'PL 3310/2026',
          title: 'Merenda escolar orgânica',
          summary:
              'Pelo menos 30% da merenda das escolas públicas comprada de agricultores familiares, sem agrotóxicos.',
          closes: now.add(const Duration(days: 51)),
          yes: 802331,
          no: 214876,
          abstain: 88010,
          chamberYes: 301,
          byState: const {
            'AM': 0.70,
            'BA': 0.76,
            'DF': 0.68,
            'MG': 0.73,
            'PE': 0.75,
            'PR': 0.69,
            'RS': 0.66,
            'SP': 0.71,
          },
        ),
      ]);

  final ValueNotifier<List<Consulta>> _consultas;
  final _petitions = ValueNotifier(const [
    Petition(
      id: 'merenda',
      title: 'Merenda orgânica em todas as escolas públicas',
      summary: 'Projeto de lei de iniciativa popular: comida de verdade, da agricultura familiar, para 40 milhões de alunos.',
      signatures: 1558910,
      goal: 1563000,
      statesReached: 4,
    ),
    Petition(
      id: 'gabinete',
      title: 'Fim do sigilo nos gastos de gabinete',
      summary: 'Todo gasto de gabinete, de vereador a senador, aberto na internet no mês seguinte.',
      signatures: 912440,
      goal: 1563000,
      statesReached: 3,
    ),
    Petition(
      id: 'saneamento',
      title: 'Saneamento básico como prioridade nacional',
      summary: 'Metas por município, com prazo e dinheiro garantido no orçamento.',
      signatures: 1103870,
      goal: 1563000,
      statesReached: 5,
    ),
  ]);
  final _channels = ValueNotifier(const [
    Channel(id: 'passe', name: 'Estudantes pelo Passe Livre', about: 'Transporte para quem estuda', members: 2300000),
    Channel(
      id: 'impostos',
      name: 'Menos Impostos, Mais Serviço',
      about: 'Imposto justo e serviço que funciona',
      members: 1700000,
    ),
    Channel(
      id: 'escola',
      name: 'Mães e Pais pela Escola Pública',
      about: 'Educação de qualidade em todo bairro',
      members: 1450000,
    ),
    Channel(id: 'orcamento', name: 'Olho no Orçamento', about: 'Acompanhar cada real público', members: 1120000),
    Channel(
      id: 'bairro',
      name: 'Segurança no Bairro',
      about: 'Vizinhos organizados por ruas mais seguras',
      members: 980000,
    ),
    Channel(id: 'saude', name: 'Saúde Fila Zero', about: 'Menos espera no SUS', members: 870000),
  ]);
  final _verified = ValueNotifier(false);

  @override
  bool get sampleData => true;
  @override
  String get place => 'Recife · Pernambuco';
  @override
  ValueListenable<List<Consulta>> get consultas => _consultas;
  @override
  ValueListenable<List<Petition>> get petitions => _petitions;
  @override
  ValueListenable<List<Channel>> get channels => _channels;
  @override
  ValueListenable<bool> get verified => _verified;

  @override
  final representatives = const [
    Representative(
      id: 'helena',
      name: 'Helena Barros',
      role: 'Deputada federal · PE',
      present: 212,
      sessions: 233,
      spending: 286400,
      spendingYear: 2026,
      spendingItems: [
        ('Divulgação do mandato', 98200),
        ('Passagens aéreas', 74500),
        ('Escritório em Recife', 61300),
        ('Combustível', 52400),
      ],
      votes: [
        RecordedVote(bill: 'PL 2841/2026', title: 'Passe livre para estudantes', choice: Choice.no),
        RecordedVote(bill: 'PL 1907/2026', title: 'Transparência nas emendas', choice: Choice.yes),
        RecordedVote(bill: 'PL 3310/2026', title: 'Merenda escolar orgânica', choice: Choice.yes),
      ],
      bills: ['PL 1175/2026 · Ciclovias em cidades médias', 'PL 2290/2026 · Atendimento noturno em postos de saúde'],
      source: 'Câmara dos Deputados',
    ),
    Representative(
      id: 'augusto',
      name: 'Augusto Teles',
      role: 'Senador · PE',
      present: 141,
      sessions: 158,
      spending: 352900,
      spendingYear: 2026,
      spendingItems: [
        ('Passagens aéreas', 121800),
        ('Escritório em Recife', 96400),
        ('Consultorias', 80300),
        ('Divulgação do mandato', 54400),
      ],
      votes: [
        RecordedVote(bill: 'PLS 418/2026', title: 'Internet nas escolas rurais', choice: Choice.yes),
        RecordedVote(bill: 'PLS 233/2026', title: 'Prazo para obras paradas', choice: Choice.abstain),
      ],
      bills: ['PLS 512/2026 · Prevenção de enchentes'],
      source: 'Senado Federal',
    ),
    Representative(
      id: 'marina',
      name: 'Marina Quintas',
      role: 'Vereadora · Recife',
      present: 88,
      sessions: 96,
      spending: 74200,
      spendingYear: 2026,
      spendingItems: [('Escritório', 38100), ('Divulgação do mandato', 21700), ('Combustível', 14400)],
      votes: [RecordedVote(bill: 'PLO 77/2026', title: 'Feiras livres aos domingos', choice: Choice.yes)],
      bills: ['PLO 102/2026 · Sombra nas paradas de ônibus'],
      source: 'Câmara Municipal',
    ),
  ];

  @override
  Future<void> verify() async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    _verified.value = true;
  }

  @override
  Future<void> vote(String consultaId, Choice choice) async =>
      _consultas.value = [for (final c in _consultas.value) c.id == consultaId ? c.withVote(choice) : c];

  /// My signature, then the last ones that take it over the line (the demo
  /// shows a petition reaching the legal threshold).
  @override
  Future<void> sign(String petitionId) async {
    void edit(Petition Function(Petition) f) =>
        _petitions.value = [for (final p in _petitions.value) p.id == petitionId ? f(p) : p];
    Petition copy(Petition p, {int add = 0, bool? signed, int? states}) => Petition(
      id: p.id,
      title: p.title,
      summary: p.summary,
      signatures: p.signatures + add,
      goal: p.goal,
      statesReached: states ?? p.statesReached,
      signed: signed ?? p.signed,
    );
    edit((p) => copy(p, add: 1, signed: true));
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
      edit((p) => copy(p, add: 380, states: i == 11 && p.signatures + 380 >= p.goal ? 5 : null));
    }
  }

  @override
  void toggleJoin(String channelId) => _channels.value = [
    for (final c in _channels.value)
      c.id == channelId
          ? Channel(id: c.id, name: c.name, about: c.about, members: c.members + (c.joined ? -1 : 1), joined: !c.joined)
          : c,
  ];
}
