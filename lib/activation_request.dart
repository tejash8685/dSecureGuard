class SavedActivationRequest {
  const SavedActivationRequest({
    required this.productId,
    required this.productCode,
    required this.status,
    this.activationId,
    this.requestDate,
    this.installationDate,
    this.reason = '',
    this.isActive = false,
    this.notifiedStatus,
  });

  final int productId;
  final String productCode;
  final String status;
  final int? activationId;
  final DateTime? requestDate;
  final DateTime? installationDate;
  final String reason;
  final bool isActive;
  final String? notifiedStatus;

  String get key => '$productId:$productCode';

  factory SavedActivationRequest.fromJson(Map<String, dynamic> json) =>
      SavedActivationRequest(
        productId: (json['productId'] as num).toInt(),
        productCode: json['productCode'] as String,
        status: json['status'] as String? ?? 'Pending',
        activationId: (json['activationId'] as num?)?.toInt(),
        requestDate: DateTime.tryParse(json['requestDate']?.toString() ?? ''),
        installationDate: DateTime.tryParse(
          json['installationDate']?.toString() ?? '',
        ),
        reason: json['reason'] as String? ?? '',
        isActive: json['isActive'] == true,
        notifiedStatus: json['notifiedStatus'] as String?,
      );

  SavedActivationRequest updated(
    Map<String, dynamic> data, {
    String? notified,
  }) => SavedActivationRequest(
    productId: productId,
    productCode: productCode,
    status: (data['status'] ?? status).toString(),
    activationId:
        ((data['activationId'] ?? data['activationID']) as num?)?.toInt() ??
        activationId,
    requestDate:
        DateTime.tryParse(data['requestDate']?.toString() ?? '') ?? requestDate,
    installationDate:
        DateTime.tryParse(data['installationDate']?.toString() ?? '') ??
        installationDate,
    reason: data['reason']?.toString() ?? '',
    isActive: data['isActive'] == true,
    notifiedStatus: notified ?? notifiedStatus,
  );

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'productCode': productCode,
    'status': status,
    'activationId': activationId,
    'requestDate': requestDate?.toIso8601String(),
    'installationDate': installationDate?.toIso8601String(),
    'reason': reason,
    'isActive': isActive,
    'notifiedStatus': notifiedStatus,
  };
}
