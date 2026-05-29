import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/supabase/supabase_storage_data_source.dart';

class _MockClient extends Mock implements SupabaseClient {}

class _MockAuth extends Mock implements GoTrueClient {}

class _MockStorage extends Mock implements SupabaseStorageClient {}

class _MockFileApi extends Mock implements StorageFileApi {}

void main() {
  late _MockClient client;
  late _MockAuth auth;
  late _MockStorage storage;
  late _MockFileApi fileApi;
  late SupabaseStorageDataSourceImpl dataSource;

  setUp(() {
    client = _MockClient();
    auth = _MockAuth();
    storage = _MockStorage();
    fileApi = _MockFileApi();
    dataSource = SupabaseStorageDataSourceImpl(client);
    when(() => client.auth).thenReturn(auth);
    when(() => client.storage).thenReturn(storage);
    when(() => storage.from('receipts')).thenReturn(fileApi);
  });

  group('uploadReceiptImage', () {
    test('should fail with AuthFailure when no user is signed in', () async {
      when(() => auth.currentUser).thenReturn(null);

      final Either<Failure, String> result =
          await dataSource.uploadReceiptImage(
        receiptId: '1',
        image: File('/tmp/missing.jpg'),
      );

      expect(
        result.swap().getOrElse(() => throw StateError('left')),
        isA<AuthFailure>(),
      );
    });
  });

  group('getSignedUrl', () {
    test('should return the signed URL on success', () async {
      when(() => fileApi.createSignedUrl('user-1/1/full.jpg', 3600))
          .thenAnswer((_) async => 'https://signed/full.jpg');

      final Either<Failure, String> result =
          await dataSource.getSignedUrl('user-1/1/full.jpg');

      expect(
        result.getOrElse(() => throw StateError('right')),
        'https://signed/full.jpg',
      );
    });

    test('should map a thrown error to a Failure', () async {
      when(() => fileApi.createSignedUrl(any(), any()))
          .thenThrow(Exception('network down'));

      final Either<Failure, String> result =
          await dataSource.getSignedUrl('user-1/1/full.jpg');

      expect(result.isLeft(), isTrue);
    });
  });

  group('deleteReceiptImage', () {
    test('should fail with AuthFailure when no user is signed in', () async {
      when(() => auth.currentUser).thenReturn(null);

      final Either<Failure, Unit> result =
          await dataSource.deleteReceiptImage('1');

      expect(
        result.swap().getOrElse(() => throw StateError('left')),
        isA<AuthFailure>(),
      );
    });
  });
}
