class Rental {
  Rental({
    required this.id,
    required this.bikeId,
    required this.userId,
    required this.startedAt,
    this.endedAt,
    this.approvedAt,
    required this.status,
    required this.plannedMinutes,
    required this.ratePerHour,
    this.estimatedCost,
    this.actualCost,
    this.penaltyFee,
  });

  final String id;
  final String bikeId;
  final String userId;
  final DateTime startedAt;   // When user submitted the request.
  final DateTime? endedAt;
  final DateTime? approvedAt; // When admin approved — countdown starts here.
  /// 'pending' | 'active' | 'ended' | 'rejected'
  final String status;
  final int plannedMinutes;
  final double ratePerHour;
  final double? estimatedCost;
  final double? actualCost;
  final double? penaltyFee;

  bool get isPending  => status == 'pending';
  bool get isActive   => status == 'active';
  bool get isEnded    => status == 'ended';
  bool get isRejected => status == 'rejected';

  /// End time based on approved_at + planned duration.
  DateTime? get scheduledEndTime =>
      approvedAt?.add(Duration(minutes: plannedMinutes));

  /// Cost accrued so far (while active). Does not include penalty.
  double currentCost(DateTime now) {
    final start = approvedAt;
    if (start == null) return estimatedCost ?? 0;
    final elapsedMin = now.difference(start).inSeconds / 60.0;
    return (elapsedMin / 60.0) * ratePerHour;
  }

  /// Overtime minutes (0 if still within planned duration).
  int overtimeMinutes(DateTime now) {
    final end = scheduledEndTime;
    if (end == null || now.isBefore(end)) return 0;
    return now.difference(end).inMinutes;
  }

  /// Penalty fee for overtime (1.5× rate for each overtime minute).
  double penaltyAmount(DateTime now) {
    final ot = overtimeMinutes(now);
    if (ot <= 0) return 0;
    return (ot / 60.0) * ratePerHour * 1.5;
  }

  factory Rental.fromJson(Map<String, dynamic> json) {
    return Rental(
      id:            json['id'].toString(),
      bikeId:        json['bike_id'].toString(),
      userId:        json['user_id'].toString(),
      startedAt:     DateTime.parse(json['started_at'].toString()),
      endedAt:       json['ended_at'] == null
                       ? null
                       : DateTime.parse(json['ended_at'].toString()),
      approvedAt:    json['approved_at'] == null
                       ? null
                       : DateTime.parse(json['approved_at'].toString()),
      status:        (json['status'] ?? 'pending').toString(),
      plannedMinutes: (json['planned_minutes'] as num?)?.toInt() ?? 60,
      ratePerHour:   (json['rate_per_hour'] as num?)?.toDouble() ?? 50.0,
      estimatedCost: (json['estimated_cost'] as num?)?.toDouble(),
      actualCost:    (json['actual_cost'] as num?)?.toDouble(),
      penaltyFee:    (json['penalty_fee'] as num?)?.toDouble(),
    );
  }
}
