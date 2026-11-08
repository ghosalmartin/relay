import SwiftUI

/// Limits how wide its content may grow. Unlike `.frame(maxWidth:)`, it doesn't
/// stretch narrower content out to the limit, so a bubble still hugs a portrait photo.
struct WidthCap: Layout {
    let limit: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: capped(proposal))
    }

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        guard let limit else { return proposal }
        return ProposedViewSize(width: min(proposal.width ?? limit, limit), height: proposal.height)
    }
}
