using System.ComponentModel;
using System.Globalization;
using System.Windows.Data;
using System.Windows.Markup;
using AUV.Windows.Core;

namespace AUV.Windows.App;

/// <summary>Live display language for WPF bindings. Changing it updates every <see cref="Tr"/> binding at once.</summary>
public sealed class Loc : INotifyPropertyChanged
{
    public static Loc Instance { get; } = new();
    public event PropertyChangedEventHandler? PropertyChanged;
    private Loc() { UiText.Changed += () => PropertyChanged?.Invoke(this, new(nameof(Language))); }
    public UiLanguage Language => UiText.Current;
    public static string T(string english, string chinese) => UiText.T(english, chinese);
    public static string Connection(ConnectionState state) => state switch
    {
        ConnectionState.Connected => T("Connected", "已连接"), ConnectionState.Reconnecting => T("Reconnecting", "正在重连"),
        ConnectionState.Stale => T("Out of date", "已过期"), ConnectionState.Disconnected => T("Disconnected", "未连接"),
        ConnectionState.Failed => T("Error", "出错"), _ => T("Unavailable", "不可用")
    };
}

/// <summary>Bilingual text next to its use: {local:Tr English, 中文}. Use quotes for text containing commas.</summary>
[MarkupExtensionReturnType(typeof(object))]
public sealed class Tr : MarkupExtension
{
    public Tr() { }
    public Tr(string en, string zh) { En = en; Zh = zh; }
    [ConstructorArgument("en")] public string En { get; set; } = "";
    [ConstructorArgument("zh")] public string Zh { get; set; } = "";
    public string? Format { get; set; }
    public override object ProvideValue(IServiceProvider serviceProvider) =>
        new Binding(nameof(Loc.Language)) { Source = Loc.Instance, Mode = BindingMode.OneWay, Converter = new Pick(En, Zh) }.ProvideValue(serviceProvider);
    private sealed class Pick(string en, string zh) : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value is UiLanguage.Chinese ? zh : en;
        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
    }
}

public sealed class DensityLabelConverter : IMultiValueConverter
{
    public static DensityLabelConverter Instance { get; } = new();
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture) => values.Length > 0 && values[0] is WizardDensity density ? DesktopController.DensityLabel(density) : "";
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

public sealed class InverseBooleanConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value is not true;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => value is not true;
}

/// <summary>ThreadOS effort labels; Ultra carries the Mac "availability not verified" marker because Windows does not read host capability.</summary>
public sealed class EffortLabelConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture) =>
        values.Length > 0 && values[0] is string effort ? ThinkingLabels.Label(effort) + (effort == "ultra" ? " · ?" : "") : "";
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) => throw new NotSupportedException();
}
