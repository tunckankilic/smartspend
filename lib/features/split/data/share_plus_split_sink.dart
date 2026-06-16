// coverage:ignore-file
// share_plus platform-plugin sink; tests inject a fake SplitShareSink instead.
import 'package:share_plus/share_plus.dart';

import 'package:smartspend/features/split/presentation/bloc/split_bloc.dart';

/// Production [SplitShareSink] backed by `share_plus`.
///
/// Kept in the data layer because it touches a platform plugin. Tests
/// inject a fake `SplitShareSink` instead — see test/.../split_bloc_test.
class SharePlusSplitSink implements SplitShareSink {
  const SharePlusSplitSink();

  @override
  Future<void> share(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
