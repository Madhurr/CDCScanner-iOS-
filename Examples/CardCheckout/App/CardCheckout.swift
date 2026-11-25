import CDCScanner
import CDCSecureFields
import SwiftUI

@main
struct CheckoutApp: App {
    var body: some Scene {
        WindowGroup { CheckoutView() }
    }
}

private struct CheckoutView: View {
    @StateObject private var form = SecureCardForm()
    @State private var token: CardToken?
    @State private var message: String?
    @State private var submitting = false
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            Form {
                if let token {
                    Section("Token created") {
                        LabeledContent("Card", value: "Visa ending in " + token.lastFour)
                        LabeledContent("Test token", value: token.value)
                            .monospacedDigit()
                        Button("Try another card") { self.token = nil }
                    }
                } else {
                    Section {
                        Button("Use test card") {
                            form.clear()
                            form.numberField?.setNumber(TestVault.number)
                            form.expiryField?.setExpiry(TestVault.expiry)
                            message = nil
                        }
                        if CardScanner.isSupported {
                            Button("Scan a test card") { scanning = true }
                        }
                    } header: {
                        Text("Local sandbox")
                    } footer: {
                        Text("Use the sample Visa and enter 123 for the security code. The test vault runs on this device.")
                    }
                    Section("Card details") {
                        VStack(alignment: .leading) {
                            Text("Card number").font(.subheadline)
                            SecureCardNumberTextField(form: form, placeholder: "Card number", masksNumberWhenInactive: true)
                                .frame(height: 48)
                        }
                        VStack(alignment: .leading) {
                            Text("Expiry date").font(.subheadline)
                            SecureExpiryTextField(form: form).frame(height: 48)
                        }
                        VStack(alignment: .leading) {
                            Text("Security code").font(.subheadline)
                            SecureCVCTextField(form: form, obscuresDigits: true).frame(height: 48)
                        }
                    }
                    Section {
                        Button(submitting ? "Creating token…" : "Create test token") {
                            Task { await submit() }
                        }
                        .disabled(!form.isComplete || submitting)
                        if let message { Text(message).foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Card checkout")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        form.numberField?.resignFirstResponder()
                        form.expiryField?.resignFirstResponder()
                        form.cvcField?.resignFirstResponder()
                    }
                }
            }
            .cardScanner(isPresented: $scanning) { card in
                form.clear()
                message = nil
                form.numberField?.setNumber(card.number)
                if let expiry = card.expiry { form.expiryField?.setExpiry(expiry) }
            } onError: { error in
                message = error.localizedDescription
            }
        }
    }

    @MainActor private func submit() async {
        guard !submitting else { return }
        submitting = true
        defer { submitting = false }
        do {
            token = try await form.tokenize(using: TestVault.tokenizer)
            form.clear()
            message = nil
        } catch TokenizationError.httpStatus(422, _) {
            message = "Choose Use test card and enter security code 123."
        } catch {
            message = "Token creation failed. Check the fields and try again."
        }
    }
}
