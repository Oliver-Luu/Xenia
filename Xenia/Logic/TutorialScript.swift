//
//  TutorialScript.swift
//  Xenia
//
//  THE tutorial content. Everything the first-run walkthrough says, in order,
//  plus the make-believe restaurant it hands the user to practise on. This file
//  is the only one to edit when the app changes: add, remove, reword or reorder
//  the pages below and `TutorialView` renders whatever it finds — it has no
//  knowledge of how many pages there are or what they contain.
//
//  Rules of thumb for editing:
//   • Bump `version` when the change is big enough that people who already went
//     through the tutorial should be shown it again on their next launch.
//   • Pull user-visible names from the app itself (`AppTab.places.label`, the
//     scenario's own values) rather than retyping them, so a rename here is one
//     rename, not two.
//   • A page with a `practice` stage shows the hands-on calculator unlocked that
//     far; the stages follow the real tip screen top to bottom.
//

import Foundation

// MARK: - Page model

/// One bullet on a tutorial page: an SF Symbol and a line of text.
struct TutorialPoint: Identifiable {
    let symbol: String
    let text: String
    var id: String { symbol + text }
}

/// How far down the practice calculator a page has unlocked. The sections appear
/// in the same order as the real tip screen, so the practice builds up across
/// pages instead of arriving all at once.
enum PracticeStage: Int, Comparable {
    case bill, ratings, rules, readout

    static func < (lhs: PracticeStage, rhs: PracticeStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Something the user is asked to actually do on a practice page. Shown as a
/// checklist row that ticks itself, and optionally gates the Next button.
enum PracticeGoal {
    case enterBill, scoreRating, engageRule

    var label: String {
        switch self {
        case .enterBill:   return String(localized: "Enter a bill amount")
        case .scoreRating: return String(localized: "Move a rating off its neutral mark")
        case .engageRule:  return String(localized: "Turn an adjustment on")
        }
    }

    func isMet(in session: PracticeSession) -> Bool {
        switch self {
        case .enterBill:   return session.hasBill
        case .scoreRating: return session.hasScoredRating
        case .engageRule:  return session.hasEngagedRule
        }
    }
}

/// A system permission the tutorial explains, then asks for in place, so the
/// prompt arrives with its reason already on screen instead of cold at launch.
/// Neither is ever required — every page carrying one is skippable, and the app
/// works without them.
enum PermissionStep {
    /// One-shot location while the app is open: recognising the place you're at.
    case locationWhenInUse
    /// Background location + notifications: the arrival reminder.
    case locationAlways

    var actionTitle: String {
        switch self {
        case .locationWhenInUse: return String(localized: "Allow while using Xenia")
        case .locationAlways:    return String(localized: "Turn on arrival reminders")
        }
    }

    var grantedTitle: String {
        switch self {
        case .locationWhenInUse: return String(localized: "Xenia can see where you are")
        case .locationAlways:    return String(localized: "Arrival reminders are on")
        }
    }

    /// Shown when iOS has the permission switched off for Xenia — the only fix
    /// from here is the Settings app.
    var deniedNote: String {
        switch self {
        case .locationWhenInUse:
            return String(localized: "Location is off for Xenia. You can still pick your place by hand every time, or turn it on in iOS Settings.")
        case .locationAlways:
            return String(localized: "Reminders need location set to \u{201C}Always\u{201D} and notifications allowed. Both are in iOS Settings.")
        }
    }

    /// Shown after "While Using" is granted but "Always" isn't — iOS often defers
    /// that second prompt rather than showing it on the spot.
    var partialNote: String {
        switch self {
        case .locationWhenInUse:
            return ""
        case .locationAlways:
            return String(localized: "iOS asks for \u{201C}Always\u{201D} separately — it may prompt you later, once you've been near a saved place. You can also set it now in iOS Settings.")
        }
    }
}

struct TutorialPage: Identifiable {
    let id: String
    /// Small uppercase line above the title — usually the tab the feature lives on.
    var eyebrow: String?
    let title: String
    let body: String
    /// Big glyph. Ignored on practice pages, where the calculator is the visual.
    var symbol: String?
    var points: [TutorialPoint] = []
    /// Set to show the hands-on calculator, unlocked to this stage.
    var practice: PracticeStage?
    /// Set to show a permission explainer with the request button in place.
    var permission: PermissionStep?
    /// A task for this page, shown as a self-ticking checklist row.
    var goal: PracticeGoal?
    /// When true, "Next" stays disabled until `goal` is met. "Skip" still works.
    var goalRequired: Bool = false
    /// A closing aside under everything else.
    var footnote: String?
}

// MARK: - The practice restaurant

/// A throwaway place, category, ratings and rules for the hands-on pages. Plain
/// values, never written to SwiftData — the tutorial can't touch the user's data.
struct PracticeScenario {

    struct Rating: Identifiable {
        let id = UUID()
        var name: String
        var maxScore: Int = RatingDefaults.maxScore
        var neutral: Int = RatingDefaults.neutralScore
        var weight: Double = RatingDefaults.weight
    }

    struct Rule: Identifiable {
        let id = UUID()
        var title: String
        var detail: String = ""
        var delta: Double
        var isStepper: Bool = false
        var maxSteps: Int = 5
    }

    var placeName: String
    var categoryName: String
    /// Reassurance shown on the practice place card.
    var note: String
    var baseTipPercent: Double
    /// Offered as a one-tap "use this" so nobody has to invent a number.
    var suggestedBill: Double
    var ratings: [Rating]
    var rules: [Rule]
}

// MARK: - Script

enum TutorialScript {

    /// Bump when the tutorial changes enough that people who have already seen it
    /// should get the new one on their next launch.
    static let version = 1

    /// `let`, not computed: the ids inside are the keys the practice session uses
    /// to remember scores and steps, so they have to stay put for the run.
    static let scenario = PracticeScenario(
        placeName: String(localized: "The Blue Fig"),
        categoryName: String(localized: "Sit-Down Restaurant"),
        note: String(localized: "A pretend place for this walkthrough. Nothing you do here is saved."),
        baseTipPercent: 18,
        suggestedBill: 86.40,
        ratings: [
            .init(name: String(localized: "Service")),
            .init(name: String(localized: "Food")),
            .init(name: String(localized: "Atmosphere")),
        ],
        // Same wording and same order the real Sit-Down Restaurant category
        // ships with: `SeedData` sorts each category's rules by delta
        // descending, so bumps come first and penalties last. The stepper is
        // here because the script's adjustments page promises one.
        rules: [
            .init(title: String(localized: "Server went above and beyond"),
                  detail: String(localized: "Menu guidance, comped something, remembered us"),
                  delta: 3),
            .init(title: String(localized: "Kitchen handled a special request"),
                  detail: String(localized: "Allergy, off-menu change, split plates"),
                  delta: 2),
            .init(title: String(localized: "Extra round"),
                  detail: String(localized: "Adds per round kept open"),
                  delta: 1, isStepper: true, maxSteps: 8),
            .init(title: String(localized: "Had to flag someone down"),
                  detail: String(localized: "Slow refills, long waits to order or pay"),
                  delta: -3),
        ]
    )

    /// Computed, so anything currency- or tab-dependent is right at the moment
    /// the tutorial opens rather than frozen at first use.
    static var pages: [TutorialPage] {
        [
            TutorialPage(
                id: "welcome",
                title: String(localized: "Welcome to Xenia"),
                body: String(localized: """
                A tip isn't one number. Xenia starts from what you'd normally \
                leave at a place like this one, then moves it for the service you \
                actually got.
                """),
                symbol: "percent",
                points: [
                    .init(symbol: "dial.medium", text: String(localized: "Set your own starting percentage per kind of place")),
                    .init(symbol: "slider.horizontal.3", text: String(localized: "Score the visit and the tip follows")),
                    .init(symbol: "mappin", text: String(localized: "Save the spots you go back to, with their own quirks")),
                ],
                footnote: String(localized: "About a minute. You can replay it any time from \(AppTab.settings.label).")
            ),

            TutorialPage(
                id: "categories",
                eyebrow: AppTab.rules.label,
                title: String(localized: "Every kind of place tips differently"),
                body: String(localized: """
                A café isn't a steakhouse. Xenia groups places into categories, \
                and each one carries its own starting tip and its own things worth \
                asking about. Six are set up for you — edit them, or make your own.
                """),
                symbol: "dial.medium",
                points: [
                    .init(symbol: "percent", text: String(localized: "A base tip: the number you'd leave without thinking")),
                    .init(symbol: "square.grid.3x1.below.line.grid.1x2", text: String(localized: "Ratings: what you score at the table, each on its own scale and worth")),
                    .init(symbol: "plusminus", text: String(localized: "Adjustments: one-off things that happened, worth a few points either way")),
                ]
            ),

            TutorialPage(
                id: "places",
                eyebrow: AppTab.places.label,
                title: String(localized: "Save the spots you go back to"),
                body: String(localized: """
                A saved place inherits its category, then bends it. Xenia can pick \
                the place out for you when you get there, so the tip screen is \
                already set up before you've put the phone down.
                """),
                symbol: "mappin",
                points: [
                    .init(symbol: "percent", text: String(localized: "Tip a bit more at your local? Override the base just there")),
                    .init(symbol: "eye.slash", text: String(localized: "Switch off a category adjustment that never applies here")),
                    .init(symbol: "plus", text: String(localized: "Add ratings and adjustments asked at this one place only")),
                    .init(symbol: "location", text: String(localized: "Arrive, and it's already selected — or pick from what's nearby")),
                ]
            ),

            TutorialPage(
                id: "practice-bill",
                eyebrow: String(localized: "Practice"),
                title: String(localized: "Let's work one out"),
                body: String(localized: """
                Here's a made-up sit-down dinner. Start where you always start: \
                punch in the bill and say how many ways it splits.
                """),
                practice: .bill,
                goal: .enterBill,
                goalRequired: true,
                footnote: String(localized: "Digits fill in from the right, cash-register style — that's a setting you can change.")
            ),

            TutorialPage(
                id: "practice-ratings",
                eyebrow: String(localized: "Practice"),
                title: String(localized: "Say how it went"),
                body: String(localized: """
                Each rating sits at a neutral mark that does nothing. Push one \
                above it and the tip lifts; pull it below and the tip trims. Try \
                the tracks and watch the figure move.
                """),
                practice: .ratings,
                goal: .scoreRating,
                goalRequired: true
            ),

            TutorialPage(
                id: "practice-rules",
                eyebrow: String(localized: "Practice"),
                title: String(localized: "Then the one-offs"),
                body: String(localized: """
                Adjustments are the things a rating can't capture. Each shows what \
                it's worth before you touch it, so there's no guessing. Some are a \
                simple on/off; some count up.
                """),
                practice: .rules,
                goal: .engageRule
            ),

            TutorialPage(
                id: "practice-readout",
                eyebrow: String(localized: "Practice"),
                title: String(localized: "Read it off"),
                body: String(localized: """
                The panel shows its working: every term that moved the tip, then \
                the bill, the tip and the total. Round it to a whole \
                \(Format.currencySymbol()) if you'd rather hand over neat money.
                """),
                practice: .readout,
                footnote: String(localized: "On the real screen this panel also saves the place and logs the tip.")
            ),

            TutorialPage(
                id: "location-while-using",
                eyebrow: String(localized: "Permission"),
                title: String(localized: "Let Xenia see where you are"),
                body: String(localized: """
                Open the \(AppTab.calculate.label) screen and Xenia takes one \
                location reading, checks it against your saved places, and — if \
                you're at one — sets the whole screen up before you've typed \
                anything. That's all it's for while the app is open.
                """),
                symbol: "location",
                points: [
                    .init(symbol: "mappin", text: String(localized: "Recognises a saved place you're standing in")),
                    .init(symbol: "magnifyingglass", text: String(localized: "Lists restaurants nearby when it's somewhere new")),
                    .init(symbol: "iphone", text: String(localized: "Readings stay on your phone — Xenia has no server to send them to")),
                ],
                permission: .locationWhenInUse,
                footnote: String(localized: "Say no and nothing breaks: you'll just pick the place from a list each time.")
            ),

            TutorialPage(
                id: "location-always",
                eyebrow: String(localized: "Permission"),
                title: String(localized: "And a nudge once you've sat down"),
                body: String(localized: """
                The reminder is the one thing Xenia can't do with the app closed \
                unless iOS lets it watch for you arriving — that's the \
                \u{201C}Always\u{201D} setting, and it's why the second prompt \
                asks for more than the first. Xenia only ever looks for places \
                you've already tipped at.
                """),
                symbol: "bell",
                points: [
                    .init(symbol: "clock", text: String(localized: "Waits the time you set per category — about 3 minutes at a café, closer to an hour at a long dinner")),
                    .init(symbol: "bell.badge", text: String(localized: "One notification, then nothing until your next visit")),
                    .init(symbol: "hand.raised", text: String(localized: "Only saved places you've tipped at before — never anywhere else you go")),
                ],
                permission: .locationAlways,
                footnote: String(localized: "Off unless you turn it on, and you can switch it back off in \(AppTab.settings.label) at any time.")
            ),

            TutorialPage(
                id: "after",
                eyebrow: "\(AppTab.history.label) · \(AppTab.settings.label)",
                title: String(localized: "What Xenia keeps"),
                body: String(localized: """
                Finishing a tip offers to save the place and log what you left. The \
                log is a plain record of where you were, what you paid and how you \
                scored it — handy when you're back and can't remember.
                """),
                symbol: "list.bullet.rectangle",
                points: [
                    .init(symbol: "dollarsign.circle", text: String(localized: "Currency, distance units, and whether tips start as a percentage or cash")),
                    .init(symbol: "arrow.uturn.backward", text: String(localized: "Deleted something by mistake? Recently Deleted holds it for 30 days")),
                ]
            ),

            TutorialPage(
                id: "done",
                title: String(localized: "That's the whole app"),
                body: String(localized: """
                Pick a place, put in the bill, say how it went. Everything else is \
                there for when you want it.
                """),
                symbol: "checkmark",
                footnote: String(localized: "\(AppTab.settings.label) → Tutorial → Replay the tutorial, whenever you want it again.")
            ),
        ]
    }
}
