import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ReceiptCaptureSource: String, Identifiable {
    case camera
    case library

    var id: String { rawValue }
}

struct ReceiptCaptureView: View {
    let source: ReceiptCaptureSource
    var onFinish: (Result<ReceiptOCR.Suggestion, ReceiptOCR.Failure>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isReading = false
    @State private var libraryPresented = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var didComplete = false

    var body: some View {
        NavigationStack {
            ZStack {
                if isReading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Zettel wird gelesen…")
                            .font(.body.weight(.medium))
                        Text("Nur auf diesem iPhone, ohne Internet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else if source == .camera {
                    CameraPicker(
                        onImage: { process($0) },
                        onCancel: { finish(.failure(.cancelled)) }
                    )
                    .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.largeTitle)
                            .foregroundStyle(.teal)
                        Text("Foto aus der Mediathek wählen")
                            .font(.headline)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("Zettel scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        finish(.failure(.cancelled))
                    }
                    .disabled(isReading)
                }
            }
            .photosPicker(
                isPresented: $libraryPresented,
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            )
            .onAppear {
                if source == .library {
                    libraryPresented = true
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .onChange(of: libraryPresented) { _, presented in
                if source == .library, !presented, selectedPhoto == nil, !isReading, !didComplete {
                    finish(.failure(.cancelled))
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isReading = true
        do {
            if let loaded = try await item.loadTransferable(type: ReceiptImage.self) {
                await recognize(loaded.image)
            } else if let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) {
                await recognize(image)
            } else {
                finish(.failure(.unreadable))
            }
        } catch {
            finish(.failure(.unreadable))
        }
    }

    private func process(_ image: UIImage) {
        isReading = true
        Task { await recognize(image) }
    }

    private func recognize(_ image: UIImage) async {
        do {
            let suggestion = try await ReceiptOCR.recognize(image)
            finish(.success(suggestion))
        } catch let failure as ReceiptOCR.Failure {
            finish(.failure(failure))
        } catch {
            finish(.failure(.visionFailed))
        }
    }

    private func finish(_ result: Result<ReceiptOCR.Suggestion, ReceiptOCR.Failure>) {
        guard !didComplete else { return }
        didComplete = true
        onFinish(result)
        dismiss()
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        } else {
            picker.sourceType = .photoLibrary
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private struct ReceiptImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let image = UIImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return ReceiptImage(image: image)
        }
    }
}
