import SwiftUI

// MARK: - Action Cards Row

struct ActionCardsRow: View {
    let convention: WindowKeyConvention

    var body: some View {
        HStack(spacing: 12) {
            DisplaysCard(convention: convention)
            SpacesCard(convention: convention)
            UndoCard(convention: convention)
        }
    }
}
