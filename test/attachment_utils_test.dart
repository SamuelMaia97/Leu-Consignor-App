import 'package:flutter_test/flutter_test.dart';
import 'package:leu_consignor_app/src/models/contract_record.dart';
import 'package:leu_consignor_app/src/utils/attachment_utils.dart';

void main() {
  group('AttachmentUtils', () {
    test('deduplicates attachments by type and path', () {
      final attachments = AttachmentUtils.mergeUnique(
        [ContractAttachment(path: '/tmp/passport.jpg', type: UploadType.passport)],
        [ContractAttachment(path: '/tmp/passport.jpg', type: UploadType.passport)],
      );

      expect(attachments, hasLength(1));
    });

    test('removes attachment by identity key', () {
      final target = ContractAttachment(path: '/tmp/item.jpg', type: UploadType.product);
      final attachments = AttachmentUtils.remove([
        target,
        ContractAttachment(path: '/tmp/passport.jpg', type: UploadType.passport),
      ], target);

      expect(attachments, hasLength(1));
      expect(attachments.first.type, UploadType.passport);
    });
  });
}
