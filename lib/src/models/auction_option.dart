class AuctionOption {
  const AuctionOption({
    required this.auctionId,
    required this.auctionNumber,
    required this.auctionType,
    required this.displayName,
  });

  final int auctionId;
  final int auctionNumber;
  final int auctionType;
  final String displayName;

  factory AuctionOption.fromJson(Map<String, dynamic> json) => AuctionOption(
        auctionId: _toInt(json['auction_id'] ?? json['auctionId'] ?? json['AuctionId']) ?? 0,
        auctionNumber: _toInt(json['auction_number'] ?? json['auctionNumber'] ?? json['AuctionNumber']) ?? 0,
        auctionType: _toInt(json['auction_type'] ?? json['auctionType'] ?? json['AuctionType']) ?? 0,
        displayName: (json['displayName'] ?? json['DisplayName'])?.toString() ?? '',
      );

  static int? _toInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
