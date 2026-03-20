import Foundation

enum PlanFormatting {
    static func nextUpSubtitle(plan: Plan) -> String {
        if let at = plan.scheduledAt {
            let df = DateFormatter()
            df.dateFormat = "EEE MMM d"
            let tf = DateFormatter()
            tf.dateFormat = "h:mm a"
            let place = plan.placeName.map { $0 + " · " } ?? ""
            return "\(place)\(df.string(from: at).lowercased()) · \(tf.string(from: at).lowercased())"
        }
        return plan.title
    }
}
