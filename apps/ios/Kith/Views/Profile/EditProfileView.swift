// EditProfileView.swift — docs/07-games-hub.md §Product rules → "Profile (2026-09-13)".
//
// Sheet from ProfileView's header: display-name rename (1–30 chars) and "Change photo"
// via PhotosPicker → ImageResizer.squareJPEG → AppModel.uploadAvatar.

import KithCore
import PhotosUI
import SwiftUI

@MainActor
struct EditProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var photoItem: PhotosPickerItem?
    @State private var isSavingName = false
    @State private var isUploadingPhoto = false

    init(currentName: String) {
        _name = State(initialValue: currentName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameIsValid: Bool {
        (1...30).contains(trimmedName.count)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display name") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("profile.edit.name")
                }

                Section("Photo") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Text("Change photo")
                            if isUploadingPhoto {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .accessibilityIdentifier("profile.edit.photo")
                    .disabled(isUploadingPhoto)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveName() }
                    }
                    .disabled(!nameIsValid || isSavingName)
                    .accessibilityIdentifier("profile.edit.save")
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task { await uploadPhoto(newItem) }
            }
        }
    }

    private func saveName() async {
        guard nameIsValid else { return }
        isSavingName = true
        defer { isSavingName = false }
        let saved = await model.updateProfile(ProfilePatch(display_name: trimmedName))
        if saved {
            dismiss()
        }
    }

    /// Reads the picker's selection as `Data`, centre-crops/resizes/re-encodes it
    /// (`ImageResizer`), then hands the JPEG to `AppModel.uploadAvatar`. Stays on the
    /// sheet either way — a toast reports success or failure (`AppModel.uploadAvatar`).
    private func uploadPhoto(_ item: PhotosPickerItem) async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = ImageResizer.squareJPEG(from: data) else {
            model.show(toast: "Couldn't read that photo.", isError: true)
            return
        }
        await model.uploadAvatar(jpeg: jpeg)
    }
}
