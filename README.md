# Pen Fight

A small, responsive 2D pen-fighting game made with Godot 4. The first version is a local single-player duel against the computer, with a hand-painted desk-board look and touch-friendly controls.

## Run it

1. Open `project.godot` in Godot 4.4 or newer.
2. Press **F6** to run the main scene, or **F5** to run the project.

## Play

- Grab anywhere along your pen and pull back opposite the direction you want it to travel.
- Pull farther for a stronger flick; release to launch. The pen stays in place while you aim, and keeps its angle while sliding.
- Pens collide side-on as well as end-on. Use solid hits to knock the computer's pen off the table; if your pen falls first, the computer wins.
- Use **Play Again** at the bottom to reset the match.

## Levels

Matches against the computer count toward a climb of 50 levels; games with only people at the desk play exactly as before and earn no XP.

- Every match earns XP: a little for playing and for each round won, much more for a win, plus bonuses for flawless wins, win streaks and boss matches.
- Your form (the share of your last ten matches you won) scales the XP of each match from x0.8 to x1.3, so a good win rate climbs faster.
- The computer plays at your level: from level to level it aims truer, weighs more shots, takes fewer risks, brings stronger pens and, from the middle levels up, plays its best shots forward with the real physics before choosing. Level 50 is the hardest.
- Ten levels make a rank (Doodler, Scribbler, Inker, Calligrapher, Pen Master, Legend). Every tenth level is a boss: once the bar is full you must beat the boss to move on. Wins over the level 50 boss earn crowns.
- Each new level pays leos (double for beating a boss) and plays a level-up celebration. Leaving a match against the computer after a point has been played counts as a loss.
- Tap the level badge or **Levels** in the lobby to see the whole climb and your record.

The board, HUD, and effects are drawn procedurally, while the pen artwork comes from the supplied SVGs in `assets/pens/`. The project uses the viewport's aspect ratio for a responsive board, supports mouse and touch input, and is configured for landscape orientation on handheld devices.

## Analytics (Android)

Android builds use Firebase Analytics. Players are asked before collection starts; they can change their choice later from **Privacy** in the lobby. Analytics is off unless they allow it, and the game does not create or send an account ID.

The game records screen views, match starts and results, level-ups, and pen unlocks. Enable Google Analytics for the Firebase project and keep its matching `google-services.json` at the project root before exporting. The Android export uses a Gradle build and includes Firebase Core and Analytics only.

## Art and font

The bundled Nunito variable font is from [Google Fonts](https://fonts.google.com/specimen/Nunito) and is licensed under the SIL Open Font License 1.1; see [`licenses/Nunito-OFL.txt`](licenses/Nunito-OFL.txt).
"# penfight" 
