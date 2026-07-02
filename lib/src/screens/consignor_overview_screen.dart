import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../domain/consignor_type.dart';
import '../models/address.dart';
import '../models/consignor.dart';
import '../models/contract_record.dart';
import '../models/payment_option.dart';
import '../models/person.dart';
import '../models/sync_status.dart';
import '../state/app_state.dart';
import '../utils/workflow_status.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/passport_status_badge.dart';
import '../widgets/page_header.dart';
import '../widgets/ready_to_sync_checklist.dart';
import '../widgets/section_card.dart';
import '../widgets/status_badge.dart';

class ConsignorOverviewScreen extends StatelessWidget {
  const ConsignorOverviewScreen({
    super.key,
    required this.consignorId,
  });

  final String consignorId;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Consignor overview',
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final consignor = state.consignorById(consignorId);
          if (consignor == null) {
            return AppEmptyState(
              title: 'Consignor not found',
              message:
                  'Return to the consignor list and choose a valid record.',
              icon: Icons.person_search_outlined,
              action: OutlinedButton.icon(
                onPressed: () => context.go('/consignors'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to consignors'),
              ),
            );
          }

          final contracts = state.contractsForConsignor(consignor.id);
          final representativeContracts = contracts
              .where(WorkflowStatus.hasRepresentative)
              .toList(growable: false);
          final issues = contracts
              .expand(
                (contract) => WorkflowStatus.readinessIssuesForContract(
                  consignor: consignor,
                  contract: contract,
                  allContracts: state.contracts,
                ),
              )
              .toList(growable: false);

          return ListView(
            children: [
              PageHeader(
                eyebrow: 'CONSIGNOR',
                title: consignor.displayName.trim().isEmpty
                    ? 'Unnamed consignor'
                    : consignor.displayName.trim(),
                trailing: _OverviewHero(
                  consignor: consignor,
                  contractCount: contracts.length,
                ),
                actions: [
                  ElevatedButton.icon(
                    onPressed: () =>
                        context.go('/contracts/${consignor.id}/new'),
                    icon: const Icon(Icons.post_add_outlined),
                    label: const Text('New contract'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go(
                      consignor.syncStatus == RecordSyncStatus.draft
                          ? '/consignors/${consignor.id}/resume'
                          : '/consignors/${consignor.id}/edit',
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit consignor'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stack = constraints.maxWidth < 1000;
                  final width = stack
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 18) / 2;
                  return Wrap(
                    spacing: 18,
                    runSpacing: 18,
                    children: [
                      SizedBox(
                        width: width,
                        child: SectionCard(
                          title: 'Profile',
                          icon: Icons.badge_outlined,
                          child: _ProfileSection(consignor: consignor),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: SectionCard(
                          title: 'Bank and payment',
                          icon: Icons.account_balance_outlined,
                          child: _BankSection(consignor: consignor),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stack = constraints.maxWidth < 1000;
                  final width = stack
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 18) / 2;
                  return Wrap(
                    spacing: 18,
                    runSpacing: 18,
                    children: [
                      SizedBox(
                        width: width,
                        child: SectionCard(
                          title: 'Legal, tax, and terms',
                          icon: Icons.rule_folder_outlined,
                          child: _LegalTermsSection(consignor: consignor),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: SectionCard(
                          title: 'Communication and preferences',
                          icon: Icons.tune_outlined,
                          child: _PreferencesSection(consignor: consignor),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (representativeContracts.isNotEmpty) ...[
                const SizedBox(height: 18),
                SectionCard(
                  title: 'Authorized representative',
                  icon: Icons.supervised_user_circle_outlined,
                  child: _RepresentativeSection(
                    contracts: representativeContracts,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SectionCard(
                title: 'Contract passport status',
                icon: Icons.assignment_ind_outlined,
                child: _ContractPassportSection(
                  consignor: consignor,
                  contracts: contracts,
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: 'Warnings',
                icon: Icons.warning_amber_rounded,
                child: ReadyToSyncChecklist(issues: issues, maxVisibleItems: 8),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: 'Contracts',
                icon: Icons.description_outlined,
                trailing: TextButton(
                  onPressed: () => context.go('/contracts/${consignor.id}'),
                  child: const Text('View contract list'),
                ),
                child: contracts.isEmpty
                    ? AppEmptyState(
                        title: 'No contracts for this consignor',
                        message:
                            'Create a new contract or run sync to analyze Abacus contracts.',
                        icon: Icons.description_outlined,
                        action: ElevatedButton.icon(
                          onPressed: () =>
                              context.go('/contracts/${consignor.id}/new'),
                          icon: const Icon(Icons.add),
                          label: const Text('New contract'),
                        ),
                      )
                    : Column(
                        children: contracts
                            .map(
                              (contract) => _ContractOverviewTile(
                                consignor: consignor,
                                contract: contract,
                                allContracts: state.contracts,
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OverviewHero extends StatelessWidget {
  const _OverviewHero({
    required this.consignor,
    required this.contractCount,
  });

  final Consignor consignor;
  final int contractCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          StatusBadge(
            label: _syncLabel(consignor.syncStatus),
            tone: _syncTone(consignor.syncStatus),
            icon: _syncIcon(consignor.syncStatus),
          ),
          StatusBadge(
            label: '$contractCount contract${contractCount == 1 ? '' : 's'}',
            tone: StatusBadgeTone.info,
            icon: Icons.description_outlined,
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.consignor});

  final Consignor consignor;

  @override
  Widget build(BuildContext context) {
    final contactPerson = _contactPersonName(consignor);
    final person = consignor.consignorInfo;
    return Column(
      children: [
        _InfoRow(label: 'Abacus ID', value: _abacusId(consignor)),
        _InfoRow(
          label: 'Customer ID',
          value: _idOrMissing(consignor.systemReferenceCustomer),
        ),
        _InfoRow(
          label: 'Consignor ID',
          value: _idOrMissing(consignor.systemReferenceConsignor),
        ),
        _InfoRow(
          label: 'Subject ID',
          value: consignor.abacusSubjectId?.toString() ?? 'Missing',
        ),
        _InfoRow(
          label: 'Existing customer',
          value: consignor.existingCustomerLabel ??
              consignor.existingCustomerId?.toString() ??
              'Missing',
        ),
        _InfoRow(
          label: 'Type',
          value: consignor.consignorType.label,
        ),
        _InfoRow(
          label: consignor.usesTradingName ? 'Organisation' : 'Name',
          value: consignor.displayName,
        ),
        if (contactPerson.isNotEmpty)
          _InfoRow(label: 'Contact person', value: contactPerson),
        _InfoRow(
          label: 'First name',
          value: person.firstName,
        ),
        _InfoRow(
          label: 'Last name',
          value: person.lastName,
        ),
        _InfoRow(
          label: 'Title ID',
          value: person.title?.toString() ?? 'Missing',
        ),
        _InfoRow(
          label: 'Salutation ID',
          value: person.salutation?.toString() ?? 'Missing',
        ),
        _InfoRow(
          label: 'Date of birth',
          value: _formatDate(person.dateOfBirth),
        ),
        _InfoRow(
          label: 'Nationality',
          value: _countryLabel(
            iso3: person.nationalityIso3,
            name: person.nationalityName,
          ),
        ),
        _InfoRow(
          label: 'Email',
          value: consignor.emailAddress.trim().isEmpty
              ? 'Missing'
              : consignor.emailAddress.trim(),
        ),
        _InfoRow(
          label: 'Phone prefix',
          value: consignor.phonePrefix,
        ),
        _InfoRow(
          label: 'Phone number',
          value: consignor.phoneNumber,
        ),
        _InfoRow(
          label: 'Phone',
          value: consignor.fullPhoneNumber.trim().isEmpty
              ? 'Missing'
              : consignor.fullPhoneNumber.trim(),
        ),
        _InfoRow(
          label: 'Address',
          value: _formatAddress(consignor.consignorAddress),
        ),
        _InfoRow(
          label: 'Country',
          value: _countryLabel(
            iso3: consignor.consignorAddress.countryIso3,
            name: consignor.consignorAddress.countryName,
          ),
        ),
      ],
    );
  }
}

class _BankSection extends StatelessWidget {
  const _BankSection({required this.consignor});

  final Consignor consignor;

  @override
  Widget build(BuildContext context) {
    final bank = consignor.bankingDetails;
    return Column(
      children: [
        _InfoRow(
          label: 'Payment method',
          value: consignor.paymentOption.label,
        ),
        _InfoRow(
          label: 'Bank',
          value: bank.bankName.trim().isEmpty ? 'Missing' : bank.bankName,
        ),
        _InfoRow(
          label: 'Account type',
          value: bank.isIban ? 'IBAN' : 'Account number',
        ),
        _InfoRow(
          label: 'Account',
          value: bank.accountNumber.trim().isEmpty
              ? 'Missing'
              : bank.accountNumber.trim(),
        ),
        _InfoRow(
          label: 'Bank country',
          value: bank.bankCountryName.trim().isNotEmpty
              ? bank.bankCountryName
              : bank.bankCountryIso3.trim().isNotEmpty
                  ? bank.bankCountryIso3
                  : 'Missing',
        ),
        _InfoRow(
          label: 'BIC/SWIFT',
          value: bank.bicSwift.trim().isEmpty ? 'Missing' : bank.bicSwift,
        ),
        _InfoRow(
          label: 'Clearing no.',
          value: bank.clearingNumber,
        ),
        _InfoRow(
          label: 'Routing no.',
          value: bank.routingNumber,
        ),
        _InfoRow(
          label: 'Beneficiary',
          value: _formatPerson(bank.beneficiary),
        ),
        _InfoRow(
          label: 'Beneficiary address',
          value: _formatAddress(bank.beneficiaryAddress),
        ),
        _InfoRow(
          label: 'Bank address',
          value: _formatAddress(bank.bankAddress),
        ),
      ],
    );
  }
}

class _LegalTermsSection extends StatelessWidget {
  const _LegalTermsSection({required this.consignor});

  final Consignor consignor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InfoRow(label: 'EORI', value: consignor.eori),
        _InfoRow(
            label: 'VAT liable', value: _formatBool(consignor.vatLiability)),
        _InfoRow(label: 'VAT number', value: consignor.vatNumber),
        _InfoRow(
          label: 'Checked by Leu',
          value: _formatBool(consignor.checkedByLeu),
        ),
        _InfoRow(
          label: 'Credit limit',
          value: _formatNumber(consignor.creditLimit),
        ),
        _InfoRow(
          label: 'Discount',
          value: _formatPercent(consignor.discount),
        ),
        _InfoRow(
          label: 'Floor terms',
          value: _formatPercent(consignor.consignmentFeeFloorAuction),
        ),
        _InfoRow(
          label: 'Web terms',
          value: _formatPercent(consignor.consignmentFeeWebAuction),
        ),
      ],
    );
  }
}

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection({required this.consignor});

  final Consignor consignor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InfoRow(
          label: 'Correspondence',
          value: _correspondenceLabel(consignor.correspondence),
        ),
        _InfoRow(
          label: 'Newsletter',
          value: _formatBool(consignor.newsletterSubscribed),
        ),
        _InfoRow(
          label: 'Ancient coins',
          value: _formatBool(consignor.ancientCoinsSubscribed),
        ),
        _InfoRow(
          label: 'World coins',
          value: _formatBool(consignor.worldCoinsSubscribed),
        ),
        _InfoRow(
          label: 'Collecting area',
          value: consignor.collectingArea,
        ),
        _InfoRow(
          label: 'References',
          value: consignor.references,
        ),
        _InfoRow(
          label: 'Last edited by',
          value: consignor.lastEditedByUsername ?? 'Missing',
        ),
        _InfoRow(
          label: 'Last edited',
          value: _formatDateTime(consignor.lastEditedAtUtc),
        ),
        _InfoRow(
          label: 'Last synced',
          value: _formatDateTime(consignor.lastSyncedUtc),
        ),
        _InfoRow(
          label: 'Remote modified',
          value: _formatDateTime(consignor.remoteLastModifiedUtc),
        ),
      ],
    );
  }
}

class _ContractPassportSection extends StatelessWidget {
  const _ContractPassportSection({
    required this.consignor,
    required this.contracts,
  });

  final Consignor consignor;
  final List<ContractRecord> contracts;

  @override
  Widget build(BuildContext context) {
    if (contracts.isEmpty) {
      return const AppEmptyState(
        title: 'No contract passports yet',
        message:
            'Create or sync contracts to see passport status per contract.',
        icon: Icons.assignment_ind_outlined,
      );
    }

    return Column(
      children: contracts.map((contract) {
        final contractNumber =
            WorkflowStatus.extractContractNumber(contract) ?? contract.pdfName;
        final passportStatus = WorkflowStatus.passportStatus(
          validUntil: consignor.passportValidUntil,
          uploads: contract.uploads.where(
            (upload) =>
                !upload.isDeleted &&
                upload.fileType == UploadType.passport &&
                !upload.kind.toLowerCase().contains('representative'),
          ),
        );

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.assignment_ind_outlined),
          title: Text(
            contractNumber.trim().isEmpty ? contract.id : contractNumber,
          ),
          subtitle: Text(
            consignor.passportValidUntil == null
                ? 'No passport valid-until date stored'
                : 'Valid until ${DateFormat('yyyy-MM-dd').format(consignor.passportValidUntil!)}',
          ),
          trailing: PassportStatusBadge(status: passportStatus, compact: true),
        );
      }).toList(),
    );
  }
}

class _RepresentativeSection extends StatelessWidget {
  const _RepresentativeSection({required this.contracts});

  final List<ContractRecord> contracts;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: contracts.map((contract) {
        final name = WorkflowStatus.representativeName(contract);
        final contractNumber =
            WorkflowStatus.extractContractNumber(contract) ?? contract.pdfName;
        final representativeFiles = contract.uploads
            .where((upload) =>
                !upload.isDeleted &&
                upload.fileType == UploadType.passport &&
                upload.kind.toLowerCase().contains('representative'))
            .length;

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.supervised_user_circle_outlined),
          title:
              Text(name.isEmpty ? 'Representative stored on contract' : name),
          subtitle: Text(
            '$contractNumber - $representativeFiles representative file${representativeFiles == 1 ? '' : 's'}',
          ),
        );
      }).toList(),
    );
  }
}

class _ContractOverviewTile extends StatelessWidget {
  const _ContractOverviewTile({
    required this.consignor,
    required this.contract,
    required this.allContracts,
  });

  final Consignor consignor;
  final ContractRecord contract;
  final List<ContractRecord> allContracts;

  @override
  Widget build(BuildContext context) {
    final contractNumber =
        WorkflowStatus.extractContractNumber(contract) ?? contract.pdfName;
    final status = _effectiveStatus(contract);
    final canEdit = contract.isEditableDraft;
    final passportStatus = WorkflowStatus.passportStatus(
      validUntil: consignor.passportValidUntil,
      uploads: contract.uploads.where(
        (upload) =>
            !upload.isDeleted &&
            upload.fileType == UploadType.passport &&
            !upload.kind.toLowerCase().contains('representative'),
      ),
    );
    final issueCount = WorkflowStatus.readinessIssuesForContract(
      consignor: consignor,
      contract: contract,
      allContracts: allContracts,
    ).length;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.description_outlined),
      title: Text(contractNumber.trim().isEmpty ? contract.id : contractNumber),
      subtitle: Text(
        '${contract.auctionDisplayName.trim().isEmpty ? 'No auction label' : contract.auctionDisplayName} - ${DateFormat('yyyy-MM-dd HH:mm').format(contract.lastModifiedUtc.toLocal())}',
      ),
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PassportStatusBadge(status: passportStatus, compact: true),
          if (issueCount > 0)
            StatusBadge(
              label: '$issueCount warning${issueCount == 1 ? '' : 's'}',
              tone: StatusBadgeTone.warning,
              icon: Icons.warning_amber_rounded,
            ),
          StatusBadge(
            label: _syncLabel(status),
            tone: _syncTone(status),
            icon: _syncIcon(status),
          ),
          OutlinedButton.icon(
            onPressed: () => _openContract(context, contract),
            icon: Icon(
              canEdit ? Icons.edit_outlined : Icons.visibility_outlined,
            ),
            label: Text(canEdit ? 'Edit draft' : 'View'),
          ),
        ],
      ),
    );
  }

  static void _openContract(BuildContext context, ContractRecord contract) {
    if (contract.isEditableDraft) {
      context.go(
        '/contracts/${contract.consignorId}/record/${contract.id}/resume',
      );
      return;
    }

    if (contract.auctionId == null) {
      context.go('/contracts/${contract.consignorId}/record/${contract.id}');
      return;
    }

    context.go('/contracts/${contract.consignorId}/${contract.auctionId}');
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Missing' : value.trim(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

String _abacusId(Consignor consignor) {
  if (consignor.systemReferenceCustomer > 0) {
    return consignor.systemReferenceCustomer.toString();
  }
  if (consignor.systemReferenceConsignor > 0) {
    return consignor.systemReferenceConsignor.toString();
  }
  if (consignor.existingCustomerId != null) {
    return consignor.existingCustomerId.toString();
  }
  return consignor.id;
}

String _contactPersonName(Consignor consignor) {
  if (!consignor.usesTradingName) return '';
  final name = consignor.consignorInfo.fullName.trim();
  if (name.toLowerCase() == consignor.displayName.trim().toLowerCase()) {
    return '';
  }
  return name;
}

String _idOrMissing(int value) => value > 0 ? value.toString() : 'Missing';

String _formatAddress(Address address) {
  final value = address.toSingleLine().trim();
  return value.isEmpty ? 'Missing' : value;
}

String _formatPerson(Person person) {
  final value = person.fullName.trim();
  return value.isEmpty ? 'Missing' : value;
}

String _formatBool(bool value) => value ? 'Yes' : 'No';

String _formatDate(DateTime? value) {
  if (value == null) return 'Missing';
  return DateFormat('yyyy-MM-dd').format(value.toLocal());
}

String _formatDateTime(DateTime? value) {
  if (value == null) return 'Missing';
  return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
}

String _formatNumber(num? value) {
  if (value == null) return 'Missing';
  final asDouble = value.toDouble();
  if (asDouble == asDouble.roundToDouble()) {
    return asDouble.toStringAsFixed(0);
  }
  return asDouble.toString();
}

String _formatPercent(num? value) {
  if (value == null) return 'Missing';
  return '${_formatNumber(value)}%';
}

String _correspondenceLabel(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return 'Missing';

  switch (normalized) {
    case 'en':
      return 'English';
    case 'de':
      return 'German';
    default:
      return value?.trim() ?? 'Missing';
  }
}

String _countryLabel({required String iso3, required String name}) {
  final cleanIso = iso3.trim();
  final cleanName = name.trim();
  if (cleanIso.isEmpty && cleanName.isEmpty) return 'Missing';
  if (cleanIso.isEmpty) return cleanName;
  if (cleanName.isEmpty) return cleanIso;
  return '$cleanName ($cleanIso)';
}

RecordSyncStatus _effectiveStatus(ContractRecord contract) {
  if (contract.syncStatus == RecordSyncStatus.syncFailed) {
    return RecordSyncStatus.syncFailed;
  }
  if (contract.syncStatus == RecordSyncStatus.draft &&
      !contract.hasRemoteReference) {
    return RecordSyncStatus.draft;
  }
  if (contract.hasLocalChanges ||
      contract.syncStatus == RecordSyncStatus.pendingSync) {
    return RecordSyncStatus.pendingSync;
  }
  if (contract.syncStatus == RecordSyncStatus.finalized) {
    return RecordSyncStatus.finalized;
  }
  if (contract.syncStatus == RecordSyncStatus.synced ||
      contract.hasRemoteReference) {
    return RecordSyncStatus.synced;
  }
  return RecordSyncStatus.draft;
}

String _syncLabel(RecordSyncStatus status) {
  switch (status) {
    case RecordSyncStatus.draft:
      return 'Draft';
    case RecordSyncStatus.pendingSync:
      return 'Pending sync';
    case RecordSyncStatus.synced:
      return 'Synced';
    case RecordSyncStatus.finalized:
      return 'Finalized';
    case RecordSyncStatus.syncFailed:
      return 'Failed';
  }
}

StatusBadgeTone _syncTone(RecordSyncStatus status) {
  switch (status) {
    case RecordSyncStatus.synced:
    case RecordSyncStatus.finalized:
      return StatusBadgeTone.success;
    case RecordSyncStatus.pendingSync:
      return StatusBadgeTone.info;
    case RecordSyncStatus.draft:
      return StatusBadgeTone.warning;
    case RecordSyncStatus.syncFailed:
      return StatusBadgeTone.error;
  }
}

IconData _syncIcon(RecordSyncStatus status) {
  switch (status) {
    case RecordSyncStatus.synced:
    case RecordSyncStatus.finalized:
      return Icons.cloud_done_outlined;
    case RecordSyncStatus.pendingSync:
      return Icons.cloud_upload_outlined;
    case RecordSyncStatus.draft:
      return Icons.edit_note_outlined;
    case RecordSyncStatus.syncFailed:
      return Icons.error_outline_rounded;
  }
}
