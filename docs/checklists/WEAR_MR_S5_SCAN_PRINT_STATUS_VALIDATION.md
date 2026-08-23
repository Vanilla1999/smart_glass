# MR-S5 scan / print / status validation

PR stack target: `refactor/wear-runtime-printer-slice` → `refactor/wear-runtime-scan-slice`.

The agent performed static review only. Flutter, analyzer, tests, Gradle, builds and device runs were not executed.

## Ownership

- [ ] `WearScanTaskSlice` is created in the aggregate root.
- [ ] `WearReviewedScanSliceReducer` is installed in the single store queue.
- [ ] `WearScanRuntime` contains no mutable barcode/product/print/status business fields.
- [ ] Printer selection is read from `WearPrinterTaskSlice`, not from a second mutable pair.
- [ ] Availability remains the only legacy feature placeholder after this MR.

## Effect ordering

- [ ] Lookup/print loading snapshot is committed before external Future starts.
- [ ] Status presenter starts only after status snapshot is committed.
- [ ] Status delay is not scheduled before typed presenter success/failure.
- [ ] Presenter failure still schedules the configured delay when one exists.
- [ ] Delay failure fails open to the already committed return target.
- [ ] Return navigation starts only after delay result.
- [ ] Slow lookup/print/presenter/delay does not block back/logout/terminal intents.

## Stale guards

For lookup, print, presenter, delay and navigation results verify all of:

- [ ] `sessionEpoch` matches.
- [ ] Expected `operationId` matches.
- [ ] Required scan phase matches.
- [ ] Required logical screen matches.
- [ ] Success and error paths use equivalent admission.
- [ ] Session clear/authorization/terminal reset clears expected operations.
- [ ] A late widget route attachment cannot clear an active lookup or print.

## Functional scenarios

- [ ] Barcode without printer pair enters one error status.
- [ ] Zero lookup results enters not-found status.
- [ ] One lookup result starts one print.
- [ ] Multiple results enter product selection with immutable products.
- [ ] Duplicate or malformed product response becomes a current lookup error and is never stored as selection data.
- [ ] Focus/page/select operate only in `productSelect/selecting`.
- [ ] Repeated barcode during lookup does not start a second lookup.
- [ ] Print success and print failure both use the same status sequence.
- [ ] Navigation failure leaves logical navigation and scan screen coherent.

## Compatibility adapter

- [ ] `WearScanRuntime.state` equals the aggregate scan slice projection.
- [ ] Voice/touch product selection dispatch the same semantic intent.
- [ ] Adapter disposal deactivates only the scan executor and resets only scan state.
- [ ] Replacing an inactive scan executor is allowed; two live scan executors are rejected.

## Suggested local commands

```bash
flutter test \
  test/wear_runtime_scan_status_sequence_test.dart \
  test/wear_scan_runtime_test.dart
```

Then run the full Wear runtime suite after the complete stack is checked locally.

## Device checks

1. Select printers, scan one-product barcode, verify exactly one print.
2. Scan duplicate barcode and select by voice and touch.
3. Turn phone screen off during lookup and during print; glasses state must continue.
4. Wake phone during print; route attachment must not cancel print.
5. Force presenter/navigation failure in a test build and verify coherent status/return.

## Stop / rollback

Do not accept the MR if presenter and delay run concurrently, if a widget entry cancels an active operation, if stale error can overwrite a newer screen, or if a second mutable scan state remains in the compatibility runtime.
