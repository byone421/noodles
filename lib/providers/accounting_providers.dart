import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/accounting_repository.dart';
import '../models/account_entry.dart';
import 'recipe_providers.dart';

final accountingRepositoryProvider = FutureProvider<AccountingRepository>(
  (ref) async =>
      AccountingRepository((await ref.watch(repositoryProvider.future)).db),
);

final accountEntriesProvider =
    FutureProvider.family<List<AccountEntry>, ({DateTime start, DateTime end})>(
      (ref, range) async =>
          (await ref.watch(accountingRepositoryProvider.future))
              .listEntries(range.start, range.end),
    );

final accountCategoriesProvider =
    FutureProvider.family<List<AccountCategory>, AccountType>(
      (ref, type) async =>
          (await ref.watch(accountingRepositoryProvider.future))
              .listCategories(type),
    );
