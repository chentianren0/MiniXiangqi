# Interaction Design

This document is for product designers, UI engineers, accessibility reviewers, artists, audio designers, and testers who shape or evaluate the Mini Xiangqi experience. It owns UI and UX behavior, navigation, Liquid Glass usage, board presentation, help, animation and motion, visual effects, sound, haptics, accessibility, localization, and platform adaptation. It does not own product feature scope, Xiangqi rules, persistence formats, engine behavior, implementation progress, or scheduling.

> **Status: Living target-MVP interaction contract**
>
> Sections outside **Need to discuss** describe accepted intended interaction direction. They do not imply that the experience has been implemented. **Need to discuss** is explicitly non-normative. Progress and delivery work belong in GitHub Issues, not in this document.

## Experience goals

- Make the board and current game state immediately understandable.
- Keep primary play actions easy to reach without obscuring the board.
- Provide a coherent experience across iOS, iPadOS, and macOS while respecting each platform’s interaction conventions.
- Treat accessibility as part of the design, not as a later visual adjustment.

## Navigation

The primary destinations are:

- **Play** for starting or resuming a game.
- **History** for reviewing and managing history records.
- **Settings** for user preferences.

The navigation presentation must adapt appropriately to iPhone, iPad, and Mac. Platform adaptation may change presentation, but it must not create different product capabilities without an explicit product decision.

## Liquid Glass

Liquid Glass is a required part of the visual and interaction direction.

- Use Liquid Glass for functional interface layers such as navigation, controls, toolbars, and contextual actions.
- Preserve board readability and interaction clarity when glass surfaces overlap or surround game content.
- Prefer platform-native behavior and adaptation over fixed imitations of one platform’s layout.
- Visual effects must not make controls, state, focus, or text harder to perceive.

## Board and game interaction

The board is the primary content during play. Its interaction design must cover:

- Board orientation and color choice.
- Selection, legal destinations, the last move, check, and game result states.
- Move input, cancellation, undo, and AI-thinking states.
- Clear prevention or explanation of unavailable actions.
- Replay controls and navigation through a history game.
- Help that explains both game concepts and interface behavior in context.

## Motion and visual effects

Animation, motion, and visual effects are part of the intended experience. They must communicate state changes and preserve the user’s understanding of the position. Reduced-motion preferences and interruption behavior must be designed alongside the default experience.

## Sound and haptics

Sound and haptics are part of the intended experience. They must reinforce meaningful actions and game events, remain optional where platform conventions expect user control, and avoid being the only way information is conveyed.

## Accessibility

The interaction design must consider:

- VoiceOver and meaningful labels, values, actions, and reading order.
- Keyboard interaction and focus behavior where supported.
- Sufficient contrast and state cues that do not rely only on color.
- Dynamic Type and text legibility.
- Reduce Motion, Reduce Transparency, and other relevant platform settings.
- Alternatives for information otherwise communicated through sound, haptics, or animation.

## Localization

The interface must be designed for localization. User-facing text must not be embedded in visual assets, and layouts must tolerate different text lengths. Terminology for Xiangqi pieces, rules, results, and controls must be consistent within each supported language.

## Platform adaptation

- iOS should support touch-first play and compact layouts.
- iPadOS should use the available space without requiring a separate product model.
- macOS should support pointer and keyboard conventions while retaining the same game behavior.
- The application does not support multiple main windows.

## Need to discuss

> The items below are questions, not requirements or implementation authorization.

- Define the navigation presentation on each device class and window size.
- Define the visual system for the board, pieces, coordinates, colors, typography, and themes.
- Define board orientation behavior for human-versus-computer and local human-versus-human games.
- Define move-entry gestures and the exact selection and legal-move feedback.
- Define the undo interaction, confirmation behavior, and AI-cancellation feedback.
- Define the active-game replacement and end-game flows.
- Define history replay controls and the import, export, and delete flows.
- Define the scope, placement, and teaching sequence of help content.
- Define the motion language, timings, interruption rules, and reduced-motion alternatives.
- Define sound events, sound design, volume or mute controls, and platform differences.
- Define haptic events and behavior on devices without haptic support.
- Define accessibility acceptance criteria and the board’s VoiceOver interaction model.
- Define supported languages, Xiangqi terminology, and localization review.
- Define how Liquid Glass behaves with contrast, Reduce Transparency, and different platform appearances.
- Define empty, loading, AI-thinking, error, corrupted-import, and destructive-action states.
