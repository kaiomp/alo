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
        Consulta(
          id: 's1',
          bill: 'PLE 412/2026',
          title: 'Ônibus intermunicipal de madrugada',
          summary: 'Linhas entre Recife, Olinda e Jaboatão rodando a noite toda, todos os dias.',
          closes: now.add(const Duration(days: 20)),
          yes: 214330,
          no: 41210,
          abstain: 9900,
          byState: const {},
          level: CivicLevel.state,
          place: 'Pernambuco',
        ),
        Consulta(
          id: 'op',
          bill: 'Orçamento participativo',
          title: 'Onde investir R\$ 2 mi no seu bairro?',
          summary: 'A prefeitura separou R\$ 2 milhões para Casa Amarela. Os moradores escolhem.',
          closes: now.add(const Duration(days: 15)),
          yes: 0,
          no: 0,
          abstain: 0,
          byState: const {},
          level: CivicLevel.city,
          place: 'Recife',
          options: const ['Iluminação nas ruas', 'Reforma da creche', 'Quadra coberta', 'Calçadas acessíveis'],
          optionVotes: const [3120, 2480, 1910, 2260],
        ),
        Consulta(
          id: 'm1',
          bill: 'PLO 88/2026',
          title: 'Ciclovia na Avenida Norte',
          summary: 'Faixa protegida para bicicletas de ponta a ponta da avenida.',
          closes: now.add(const Duration(days: 9)),
          yes: 18240,
          no: 9310,
          abstain: 1220,
          byState: const {},
          level: CivicLevel.city,
          place: 'Recife',
        ),
        Consulta(
          id: 'b1',
          bill: 'Consulta do bairro',
          title: 'Nova praça ou posto de saúde 24h?',
          summary: 'O terreno da antiga fábrica vai ganhar um uso. Os moradores decidem qual.',
          closes: now.add(const Duration(days: 6)),
          yes: 0,
          no: 0,
          abstain: 0,
          byState: const {},
          level: CivicLevel.neighbourhood,
          place: 'Casa Amarela',
          options: const ['Nova praça', 'Posto de saúde 24h'],
          optionVotes: const [497, 742],
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
    Petition(
      id: 'intermunicipal',
      title: 'Passe livre intermunicipal para estudantes',
      summary: 'Estudantes da Região Metropolitana sem pagar passagem entre cidades.',
      signatures: 61200,
      goal: 70000,
      statesReached: 0,
      level: CivicLevel.state,
      rule: 'Meta: 1% dos eleitores de Pernambuco',
    ),
    Petition(
      id: 'feira',
      title: 'Feira livre aos domingos em todos os bairros',
      summary: 'Uma feira de produtores locais por bairro, todo domingo de manhã.',
      signatures: 28400,
      goal: 58000,
      statesReached: 0,
      level: CivicLevel.city,
      rule: 'Meta: 5% dos eleitores de Recife',
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
    Channel(
      id: 'pe-agua',
      name: 'Água no Sertão',
      about: 'Cisternas e adutoras para o interior',
      members: 412000,
      level: CivicLevel.state,
    ),
    Channel(
      id: 'recife-bike',
      name: 'Recife de Bicicleta',
      about: 'Ciclovias que ligam os bairros',
      members: 96000,
      level: CivicLevel.city,
    ),
    Channel(
      id: 'casa-amarela',
      name: 'Vizinhos de Casa Amarela',
      about: 'O canal do bairro: avisos, achados e ajuda',
      members: 14300,
      level: CivicLevel.neighbourhood,
    ),
  ]);
  final _issues = ValueNotifier([
    LocalIssue(
      id: 'buraco',
      title: 'Buraco na Rua Padre Lemos',
      street: 'Em frente ao número 410',
      photo: Uri(path: 'demo/fotos/buraco.jpg'),
      supporters: 312,
      status: 'Prefeitura respondeu',
    ),
    LocalIssue(
      id: 'luz',
      title: 'Rua escura perto da escola',
      street: 'Rua Leonardo Cavalcanti',
      photo: Uri(path: 'demo/fotos/iluminacao.jpg'),
      supporters: 188,
    ),
    LocalIssue(
      id: 'calcada',
      title: 'Calçada quebrada no caminho do posto',
      street: 'Estrada do Arraial',
      photo: Uri(path: 'demo/fotos/calcada.jpg'),
      supporters: 96,
    ),
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
      level: CivicLevel.city,
    ),
    Representative(
      id: 'caio',
      name: 'Caio Lins',
      role: 'Deputado estadual · PE',
      present: 118,
      sessions: 131,
      spending: 141300,
      spendingYear: 2026,
      spendingItems: [('Escritório', 62100), ('Combustível', 41800), ('Divulgação do mandato', 37400)],
      votes: [RecordedVote(bill: 'PLE 412/2026', title: 'Ônibus intermunicipal de madrugada', choice: Choice.yes)],
      bills: ['PLE 377/2026 · Merenda regional nas escolas estaduais'],
      source: 'Assembleia Legislativa',
      level: CivicLevel.state,
    ),
    Representative(
      id: 'rosa',
      name: 'Rosa Amaral',
      role: 'Deputada estadual · PE',
      present: 125,
      sessions: 131,
      spending: 118900,
      spendingYear: 2026,
      spendingItems: [('Escritório', 54200), ('Passagens', 35700), ('Divulgação do mandato', 29000)],
      votes: [RecordedVote(bill: 'PLE 412/2026', title: 'Ônibus intermunicipal de madrugada', choice: Choice.no)],
      bills: ['PLE 401/2026 · Bibliotecas abertas à noite'],
      source: 'Assembleia Legislativa',
      level: CivicLevel.state,
    ),
    Representative(
      id: 'jorge',
      name: 'Jorge Paiva',
      role: 'Vereador · Recife',
      present: 81,
      sessions: 96,
      spending: 69800,
      spendingYear: 2026,
      spendingItems: [('Escritório', 35200), ('Divulgação do mandato', 20100), ('Combustível', 14500)],
      votes: [RecordedVote(bill: 'PLO 88/2026', title: 'Ciclovia na Avenida Norte', choice: Choice.yes)],
      bills: ['PLO 131/2026 · Bebedouros nas praças'],
      source: 'Câmara Municipal',
      level: CivicLevel.city,
    ),
  ];

  @override
  final hearings = const [
    Hearing(
      level: CivicLevel.city,
      title: 'Votação da ciclovia na Avenida Norte',
      when: 'Terça, 15h',
      where: 'Câmara Municipal do Recife',
    ),
    Hearing(
      level: CivicLevel.neighbourhood,
      title: 'O que fazer com o terreno da antiga fábrica',
      when: 'Quinta, 19h',
      where: 'Escola Municipal de Casa Amarela',
    ),
  ];

  @override
  final places = const [
    Place(CivicLevel.country, 'Brasil'),
    Place(CivicLevel.state, 'Pernambuco'),
    Place(CivicLevel.city, 'Recife'),
    Place(CivicLevel.neighbourhood, 'Casa Amarela'),
  ];

  @override
  List<String> get followedPlaces => const ['Recife', 'Casa Amarela', 'Olinda'];

  @override
  ValueListenable<List<LocalIssue>> get issues => _issues;

  @override
  void toggleSupport(String issueId) => _issues.value = [
    for (final i in _issues.value)
      i.id == issueId
          ? LocalIssue(
              id: i.id,
              title: i.title,
              street: i.street,
              photo: i.photo,
              supporters: i.supporters + (i.supported ? -1 : 1),
              status: i.status,
              supported: !i.supported,
            )
          : i,
  ];

  @override
  Future<void> voteOption(String consultaId, int option) async =>
      _consultas.value = [for (final c in _consultas.value) c.id == consultaId ? c.withOption(option) : c];

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
    edit((p) => p.copyWith(add: 1, signed: true));
    // The national demo petition then crosses its threshold.
    if (_petitions.value.firstWhere((p) => p.id == petitionId).level != CivicLevel.country) return;
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
      edit((p) => p.copyWith(add: 380, states: i == 11 && p.signatures + 380 >= p.goal ? 5 : null));
    }
  }

  @override
  void toggleJoin(String channelId) => _channels.value = [
    for (final c in _channels.value)
      c.id == channelId
          ? Channel(
              id: c.id,
              name: c.name,
              about: c.about,
              members: c.members + (c.joined ? -1 : 1),
              joined: !c.joined,
              level: c.level,
            )
          : c,
  ];
}
