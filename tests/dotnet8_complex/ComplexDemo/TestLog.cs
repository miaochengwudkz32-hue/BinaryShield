using System;
using System.Globalization;
using System.IO;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.VisualTree;

namespace ComplexDemo
{
    // Test log written next to the exe. The UI test reads it to check what the app really did.
    // "screen" lines are physical screen pixels from Avalonia's PointToScreen, so the test can click
    // them directly. This avoids guessing the window's content offset, which differs on WSLg.
    public static class TestLog
    {
        private static readonly string LogPath = Path.Combine(AppContext.BaseDirectory, "app_test.log");

        public static void Write(string message)
        {
            try
            {
                File.AppendAllText(LogPath, DateTime.Now.ToString("HH:mm:ss.fff") + " " + message + Environment.NewLine);
            }
            catch
            {
                // Logging must never break the UI.
            }
        }

        // Writes the window origin on screen, then the centre of every named, visible control and the
        // first visible DataGrid row, both in device-independent pixels (pos) and in screen pixels (screen).
        public static void LogLayout(string label, Window window)
        {
            var origin = window.PointToScreen(new Point(0, 0));
            Write("origin " + label + " " + origin.X + " " + origin.Y);

            foreach (var control in window.GetVisualDescendants().OfType<Control>())
            {
                if (string.IsNullOrEmpty(control.Name) || control.Bounds.Width <= 0 || control.Bounds.Height <= 0)
                {
                    continue;
                }
                LogCenter(label, control.Name, control, window);
            }

            // Topmost visible DataGrid row. Avalonia 11.0.10's DataGridRow has no public Index,
            // and all rows share one parent, so their Bounds.Top values are comparable.
            var row = window.GetVisualDescendants().OfType<DataGridRow>()
                .Where(r => r.Bounds.Height > 0)
                .OrderBy(r => r.Bounds.Top)
                .FirstOrDefault();
            if (row != null)
            {
                LogCenter(label, "RowFirst", row, window);
            }
        }

        private static void LogCenter(string label, string name, Control control, Visual relativeTo)
        {
            var centre = new Point(control.Bounds.Width / 2, control.Bounds.Height / 2);
            var point = control.TranslatePoint(centre, relativeTo);
            if (point == null)
            {
                return;
            }
            Write("pos " + label + " " + name + " " + F(point.Value.X) + " " + F(point.Value.Y));

            var screen = control.PointToScreen(centre);
            Write("screen " + label + " " + name + " " + screen.X + " " + screen.Y);
        }

        private static string F(double value) => value.ToString("F1", CultureInfo.InvariantCulture);
    }
}
