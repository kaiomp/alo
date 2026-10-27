import 'package:flutter/foundation.dart';

enum Choice { yes, no, abstain }

/// How a representative voted on one bill.
class RecordedVote {
  const RecordedVote({required this.bill, required this.title, required this.choice});
  final String bill;
  final String title;
  final Choice choice;
}

/// Someone elected for my state or city, as the open data describes them.
class Representative {
  const Representative({
    required this.id,
    required this.name,
    required this.role,
    required this.present,
    required this.sessions,
    required this.spending,
    required this.spendingYear,
    required this.spendingItems,
    required this.votes,
    required this.bills,
    required this.source,
  });
  final String id;
  final String name;

  /// "Deputada federal · PE".
  final String role;
  final int present;
  final int sessions;

  /// Reais.
  final int spending;
  final int spendingYear;

  /// (what, reais), largest first as the source lists them.
  final List<(String, int)> spendingItems;
  final List<RecordedVote> votes;
  final List<String> bills;

  /// Where the facts come from ("Câmara dos Deputados").
  final String source;
}

/// A question to the people on a bill in Congress.
class Consulta {
  const Consulta({
    required this.id,
    required this.bill,
    required this.title,
    required this.summary,
    required this.closes,
    required this.yes,
    required this.no,
    required this.abstain,
    required this.byState,
    this.chamberYes,
    this.chamberTotal = 513,
    this.myVote,
  });
  final String id;
  final String bill;
  final String title;
  final String summary;
  final DateTime closes;
  final int yes;
  final int no;
  final int abstain;

  /// State abbreviation → share voting yes (0..1), shown in alphabetical
  /// order: Voz never ranks.
  final Map<String, double> byState;

  /// Deputies who voted yes, once the Chamber has voted.
  final int? chamberYes;
  final int chamberTotal;
  final Choice? myVote;

  int get total => yes + no + abstain;
  double get yesShare => total == 0 ? 0 : yes / total;

  Consulta withVote(Choice c) => Consulta(
    id: id,
    bill: bill,
    title: title,
    summary: summary,
    closes: closes,
    yes: yes + (c == Choice.yes ? 1 : 0),
    no: no + (c == Choice.no ? 1 : 0),
    abstain: abstain + (c == Choice.abstain ? 1 : 0),
    byState: byState,
    chamberYes: chamberYes,
    chamberTotal: chamberTotal,
    myVote: c,
  );
}

/// A popular-initiative bill collecting verified signatures.
class Petition {
  const Petition({
    required this.id,
    required this.title,
    required this.summary,
    required this.signatures,
    required this.goal,
    required this.statesReached,
    this.signed = false,
  });
  final String id;
  final String title;
  final String summary;
  final int signatures;

  /// 1% of the electorate.
  final int goal;

  /// States with at least 0.3% of their voters signing (5 needed).
  final int statesReached;
  final bool signed;
}

/// A big open channel for a movement or cause.
class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.about,
    required this.members,
    this.joined = false,
  });
  final String id;
  final String name;
  final String about;
  final int members;
  final bool joined;
}

/// The Voz tab: follow representatives, vote in consultations, sign
/// petitions, join movements. Limit: only the demo implements it today; the
/// real one reads Câmara, Senado, TSE and Portal da Transparência open data
/// and verifies people through gov.br.
abstract interface class CivicService {
  /// The data is invented; screens then say "Dados de exemplo".
  bool get sampleData;

  /// "Recife · Pernambuco".
  String get place;
  List<Representative> get representatives;
  ValueListenable<List<Consulta>> get consultas;
  ValueListenable<List<Petition>> get petitions;
  ValueListenable<List<Channel>> get channels;

  /// One verified person, one vote; the vote itself stays anonymous.
  ValueListenable<bool> get verified;
  Future<void> verify();
  Future<void> vote(String consultaId, Choice choice);
  Future<void> sign(String petitionId);
  void toggleJoin(String channelId);
}
