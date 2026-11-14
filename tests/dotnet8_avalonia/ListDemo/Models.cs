using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace ListDemo
{
    // Public properties: KeepPublicApi=true in Obfuscar keeps these names,
    // so reflection-based XAML bindings still resolve after protection.
    public class ItemModel
    {
        public int Index { get; set; }
        public string Name { get; set; }
        public string Detail { get; set; }
    }

    public class MainViewModel : INotifyPropertyChanged
    {
        private int _clickCount;
        private string _status;

        public MainViewModel()
        {
            for (int i = 0; i < 10000; i++)
            {
                Items.Add(new ItemModel
                {
                    Index = i,
                    Name = "Item " + i,
                    Detail = "Detail " + (i * 7)
                });
            }
            Status = "Total: " + Items.Count + " items";
        }

        public ObservableCollection<ItemModel> Items { get; } = new ObservableCollection<ItemModel>();

        public int ClickCount
        {
            get => _clickCount;
            set
            {
                if (_clickCount != value)
                {
                    _clickCount = value;
                    OnPropertyChanged();
                }
            }
        }

        public string Status
        {
            get => _status;
            set
            {
                if (_status != value)
                {
                    _status = value;
                    OnPropertyChanged();
                }
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;

        private void OnPropertyChanged([CallerMemberName] string name = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }
}
