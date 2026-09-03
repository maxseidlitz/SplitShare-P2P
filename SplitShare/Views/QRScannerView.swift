import SwiftUI
import VisionKit

struct QRScannerView: View {
    var onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                    DataScannerRepresentable(onScan: { value in
                        onScan(value)
                        dismiss()
                    })
                } else {
                    ContentUnavailableView {
                        Label("Kamera nicht verfügbar", systemImage: "qrcode.viewfinder")
                    } description: {
                        Text("QR-Codes scannen funktioniert auf einem echten iPhone mit Kamerazugriff.")
                    }
                }
            }
            .navigationTitle("QR-Code scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        weak var scanner: DataScannerViewController?
        private var didHandle = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(items: addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(items: [item])
        }

        private func handle(items: [RecognizedItem]) {
            guard !didHandle else { return }
            for item in items {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    didHandle = true
                    scanner?.stopScanning()
                    onScan(value)
                    return
                }
            }
        }
    }
}

struct IdentityQRCodeView: View {
    let payload: QRIdentity.Payload

    var body: some View {
        VStack(spacing: 16) {
            if let image = QRIdentity.image(from: payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 260)
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text(payload.displayName)
                .font(.headline)
            Text("Andere scannen diesen Code, um dich in eine Gruppe einzuladen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
