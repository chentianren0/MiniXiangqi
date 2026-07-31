// Pictures of the board, drawn offscreen.
//
// This is the Windows frontend's answer to a problem it cannot otherwise solve.
// A WinUI 3 process cannot be launched over SSH — session 0 has no interactive
// desktop and the Windows App SDK's input stack fail-fasts before any of this
// repository's code runs — so on the only Windows machine this project has,
// nobody can look at the board. What this does instead is render the real
// board-drawing code to PNG files at representative sizes and states, in a
// headless process, so that a reviewer can see what the window draws without
// the window.
//
// Two things make these pictures evidence rather than illustration.
//
//   * The picture is BoardPainter.Draw, which is exactly what the window's
//     CanvasControl calls. The only difference is which drawing session the
//     painter was handed.
//   * The *scene* is PlaySession's, reached by clicking points through the same
//     Tap the window calls. So every marker in every picture is the core's own
//     answer about a real position, and no placement, legal-move set or check
//     state below was written out by hand — a board picture that showed a
//     destination the rules do not offer would be worse than no picture.
//
// **Where it can run.** Win2D needs a Direct2D device, and Direct2D refuses in
// session 0: every way into CanvasDevice answers DXGI_ERROR_NOT_CURRENTLY_
// AVAILABLE (0x887A0022) over SSH on the development VM, while raw D3D11 on
// WARP succeeds in the same process — so it is the graphics stack's session
// rule rather than the absence of a GPU. A GitHub Actions Windows runner has a
// console session, and Win2D works there, which is why the Windows frontend
// workflow is what produces the committed evidence.

using Microsoft.Graphics.Canvas;
using MiniXiangqi.Board;
using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;
using MiniXiangqi.Play;

namespace MiniXiangqi.Shots;

internal static class Program
{
    private static int Main(string[] args)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        string assets = Argument(args, "--assets") ?? Path.Combine(AppContext.BaseDirectory, "assets");
        string store = Argument(args, "--store")
            ?? Path.Combine(Path.GetTempPath(), "mxq-shots-" + Guid.NewGuid().ToString("N"));
        string directory = Argument(args, "--out") ?? Path.Combine(AppContext.BaseDirectory, "shots");
        Directory.CreateDirectory(directory);

        Console.WriteLine("Mini Xiangqi — offscreen board renders");
        Console.WriteLine("======================================");
        Console.WriteLine($"assets         {assets}");
        Console.WriteLine($"store          {store}");
        Console.WriteLine($"out            {directory}");
        Console.WriteLine();

        CanvasDevice device;
        try
        {
            // The software renderer, because a runner has no GPU worth asking
            // for and the picture must not depend on one.
            device = new CanvasDevice(forceSoftwareRenderer: true);
        }
        catch (Exception failure)
        {
            Console.WriteLine($"No Direct2D device: {failure.GetType().Name} 0x{failure.HResult:X8}");
            Console.WriteLine("This process has no session that Direct2D will serve.");
            Console.WriteLine("MXQ_SHOTS_UNAVAILABLE");
            return 2;
        }

        try
        {
            using MiniXiangqiCore core = MiniXiangqiCore.Start(store, assets);
            Shoot(core, device, directory);
        }
        finally
        {
            device.Dispose();
            try
            {
                Directory.Delete(store, recursive: true);
            }
            catch (IOException)
            {
                // A scratch store; failing to remove it is not a result.
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        Console.WriteLine();
        Console.WriteLine("MXQ_SHOTS_OK");
        return 0;
    }

    private static void Shoot(MiniXiangqiCore core, CanvasDevice device, string directory)
    {
        Studio studio = new(core, device, directory);

        // The board at the accepted 44-point pitch floor, and at a size an
        // ordinary desktop window actually gives it.
        studio.Shot("start-floor", 44, _ => { });
        studio.Shot("start-large", 84, _ => { });

        // Red at the top, which is what a human playing Black sees. A
        // coordinate is absolute, so the labels re-order and never rename.
        studio.Shot("start-flipped", 84, play => play.FlipBoard());

        // The pointer's own report of where it is, which is never a game state
        // and never previews what is legal.
        studio.Shot("pointer-hover", 84, play => play.Hover(new Square(3, 3)));

        // A selection and its legal destinations, on a position a few plies in.
        // The piece chosen is whichever of the mover's own has the most legal
        // moves, so the picture shows the marker vocabulary under load rather
        // than a piece with two places to go.
        studio.Shot("selection-and-destinations", 84, play =>
        {
            Advance(play, 6);
            play.Tap(Busiest(play));
        });

        // A capture available: the dashed ring around an enemy disc, beside the
        // filled dots of the same piece's quiet moves.
        studio.Shot("capture-available", 84, play =>
        {
            if (Reach(play, 12, () => Capturable(play).Count > 0))
            {
                play.Tap(Capturable(play)[0]);
            }
        });

        // A general in check: the double ring, which the turn status's 将军
        // token accompanies during play.
        studio.Shot("check", 84, play => Reach(play, 24, () => play.Position.InCheck));

        // The pre-start state's preview, both ways round.
        //
        // **These are drawn and uploaded, and they are deliberately not
        // committed as evidence.** A pre-start preview *is* the frozen initial
        // board, so each comes out byte-identical to start-large and
        // start-flipped above — the run proves the claim, which is that the
        // pre-start page draws the real board at the real position and that the
        // draft's orientation rule reaches the same picture Free Play's flip
        // control reaches, and committing a second copy of a file already in the
        // repository would add bytes rather than pixels. The Play home has no
        // picture at all, because it has no board on it: that is the contract's
        // own direction for it, and its evidence is what the smoke harness
        // composes.
        studio.Preview("setup-preview", 84, PlayMode.HumanVersusAi, FirstMoverChoice.HumanFirst);
        studio.Preview("setup-preview-ai-first", 84, PlayMode.HumanVersusAi, FirstMoverChoice.AiFirst);
    }

    /// <summary>
    /// Where a picture is made: a Free Play game, driven to the state the
    /// caller wants through the same clicks the window makes, then drawn.
    /// </summary>
    private sealed class Studio(MiniXiangqiCore core, CanvasDevice device, string directory)
    {
        internal void Shot(string name, double pitch, Action<PlaySession> arrange)
        {
            GameSession game = core.Create(
                Mxq.MXQ_PLAY_MODE_FREE_PLAY,
                Mxq.MXQ_COLOR_NONE,
                Mxq.MXQ_AI_LEVEL_NONE,
                Mxq.MXQ_FIRST_MOVER_NONE,
                0);

            BoardScene scene;
            int plies;
            using (PlaySession play = new(core, game, new PumpScheduler()))
            {
                arrange(play);
                scene = play.Scene;
                plies = play.MoveRecord.Count;

                // One active game at a time, so each picture's game is filed
                // before the next one is created.
                core.ArchiveAndClear(game);
            }

            Save(name, scene, pitch, plies);
        }

        /// <summary>
        /// A pre-start preview, reached the way the page reaches it: a mode
        /// chosen on the Play home, a first-mover choice made in the draft, and
        /// the scene the page then draws. No game is created — a pre-start state
        /// is not an active game — so nothing here is filed and nothing is
        /// played.
        /// </summary>
        internal void Preview(string name, double pitch, PlayMode mode, FirstMoverChoice choice)
        {
            using PlayFlow flow = new(core, new PumpScheduler(), NoPreferences.Instance);
            flow.Choose(mode);
            flow.ChooseFirstMover(choice);
            Save(name, flow.PreviewScene, pitch, plies: 0);
        }

        private void Save(string name, BoardScene scene, double pitch, int plies)
        {
            BoardGeometry geometry = new(pitch);
            float side = (float)geometry.BlockSide;
            using CanvasRenderTarget target = new(device, side, side, 96);
            using (CanvasDrawingSession session = target.CreateDrawingSession())
            {
                BoardPainter.Draw(session, scene, geometry, BoardStyle.Traditional);
            }

            string path = Path.Combine(directory, name + ".png");
            target.SaveAsync(path, CanvasBitmapFileFormat.Png).AsTask().GetAwaiter().GetResult();
            Console.WriteLine(
                $"    {name,-28} pitch {pitch,3}  {side:F0}x{side:F0}  {plies,3} ply  "
                + $"{new FileInfo(path).Length,7:N0} bytes");
        }
    }

    // Driving the board.

    /// <summary>
    /// Play <paramref name="plies"/> half-moves, each the first of the core's
    /// own legal set in sorted order and each committed by clicking its origin
    /// and then its destination — the same path a player's two clicks take.
    /// </summary>
    private static void Advance(PlaySession play, int plies)
    {
        for (int ply = 0; ply < plies; ply++)
        {
            List<string> legal = [.. play.LegalMoves()];
            legal.Sort(StringComparer.Ordinal);
            if (legal.Count == 0 || Move.Parse(legal[0]) is not { } move)
            {
                return;
            }

            play.Tap(move.From);
            play.Tap(move.To);
        }
    }

    /// <summary>
    /// Play until <paramref name="wanted"/> holds, trying each legal move and
    /// taking back the ones that do not get there. Undo is the core's, so the
    /// position walked back to is the position that was there.
    /// </summary>
    private static bool Reach(PlaySession play, int plies, Func<bool> wanted)
    {
        for (int ply = 0; ply < plies; ply++)
        {
            List<string> legal = [.. play.LegalMoves()];
            legal.Sort(StringComparer.Ordinal);

            string? fallback = null;
            foreach (string text in legal)
            {
                if (Move.Parse(text) is not { } move)
                {
                    continue;
                }

                play.Tap(move.From);
                play.Tap(move.To);
                if (wanted())
                {
                    return true;
                }

                fallback ??= text;
                play.Undo();
            }

            if (fallback is null || Move.Parse(fallback) is not { } chosen)
            {
                return false;
            }

            play.Tap(chosen.From);
            play.Tap(chosen.To);
        }

        return wanted();
    }

    /// <summary>The mover's own piece with the most legal moves.</summary>
    private static Square Busiest(PlaySession play)
    {
        Dictionary<Square, int> counts = [];
        foreach (string text in play.LegalMoves())
        {
            if (Move.Parse(text) is { } move)
            {
                counts[move.From] = counts.GetValueOrDefault(move.From) + 1;
            }
        }

        return counts.OrderByDescending(entry => entry.Value)
            .ThenBy(entry => entry.Key.Name, StringComparer.Ordinal)
            .First()
            .Key;
    }

    /// <summary>The mover's own pieces that can take something.</summary>
    private static List<Square> Capturable(PlaySession play)
    {
        List<Square> origins = [];
        foreach (string text in play.LegalMoves())
        {
            if (Move.Parse(text) is { } move && play.Scene.Placement[move.To] is not null
                && !origins.Contains(move.From))
            {
                origins.Add(move.From);
            }
        }

        origins.Sort((left, right) => string.CompareOrdinal(left.Name, right.Name));
        return origins;
    }

    private static string? Argument(string[] args, string name)
    {
        int index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }
}
