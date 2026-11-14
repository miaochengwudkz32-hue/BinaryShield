namespace ComplexDemo
{
    // Public properties: KeepPublicApi=true in Obfuscar keeps these names,
    // so XAML bindings still resolve after protection.
    public class CustomerModel
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Region { get; set; }
        public decimal Balance { get; set; }
    }
}
