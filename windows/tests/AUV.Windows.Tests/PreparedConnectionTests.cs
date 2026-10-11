using System.Text;
using AUV.Windows.Core;

namespace AUV.Windows.Tests;

public sealed class PreparedConnectionTests
{
    private const string Claude = """{"schemaVersion":1,"claudeVersion":"2.1.0-beta","fiveHour":{"usedPercentage":25.5,"resetsAtEpochSeconds":1800000000},"sevenDay":null,"observedAt":1791600000000.25}""";
    private const string Antigravity = """{"command":{"name":"usage","data":{"description":"Quota","groups":[{"name":"Model group","description":"Plan quotas","buckets":[{"id":"model:daily","name":"Daily","window":"Day","remaining_fraction":0.25,"reset_time":"2026-10-11T00:00:00Z"}]}]}},"num_turns":0,"conversation_id":"","usage":{"input_tokens":0,"output_tokens":0}}""";

    [Fact] public void ClaudePacketPreservesRemainingSemanticsAndFractionalObservation()
    {
        var packet = PreparedClaudePacketDecoder.Decode(Encoding.UTF8.GetBytes(Claude));
        Assert.Equal(74.5, packet.FiveHour!.RemainingPercent); Assert.Null(packet.SevenDay);
        Assert.Equal(DateTimeOffset.FromUnixTimeMilliseconds(1791600000000).AddTicks(2500), packet.ObservedAt);
    }

    [Theory]
    [InlineData("\"schemaVersion\":1", "\"schemaVersion\":2")]
    [InlineData("\"usedPercentage\":25.5", "\"usedPercentage\":101")]
    [InlineData("\"resetsAtEpochSeconds\":1800000000", "\"resetsAtEpochSeconds\":4102444801")]
    [InlineData("\"claudeVersion\":\"2.1.0-beta\"", "\"claudeVersion\":false")]
    [InlineData("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1")]
    [InlineData("\"sevenDay\":null", "\"sevenDay\":null,\"transcript\":[]")]
    public void ClaudeRejectsInvalidOrExcessFields(string from, string to) =>
        Assert.Throws<InvalidDataException>(() => PreparedClaudePacketDecoder.Decode(Encoding.UTF8.GetBytes(Claude.Replace(from, to))));

    [Fact] public void AntigravityPacketUsesRemainingFractionWithoutAdmittingTransport()
    {
        var bucket = Assert.Single(PreparedAntigravityDecoder.Decode(Encoding.UTF8.GetBytes(Antigravity), "agy-1.1.11"));
        Assert.Equal("model:daily", bucket.Id); Assert.Equal(25, bucket.RemainingPercent); Assert.Equal("Daily", bucket.DisplayLabel);
    }

    [Theory]
    [InlineData("\"num_turns\":0", "\"num_turns\":1")]
    [InlineData("\"input_tokens\":0", "\"input_tokens\":0.00000000000000000000000000001")]
    [InlineData("\"input_tokens\":0", "\"input_tokens\":false")]
    [InlineData("\"conversation_id\":\"\"", "\"conversation_id\":\"session\"")]
    [InlineData("\"remaining_fraction\":0.25", "\"remaining_fraction\":1.01")]
    [InlineData("\"name\":\"Model group\"", "\"name\":false")]
    [InlineData("\"window\":\"Day\"", "\"window\":\"\"")]
    [InlineData("\"reset_time\":\"2026-10-11T00:00:00Z\"", "\"reset_time\":\"2026-10-11T00:00:00Z\\n\"")]
    public void AntigravityRejectsWorkAndMalformedQuota(string from, string to) =>
        Assert.Throws<InvalidDataException>(() => PreparedAntigravityDecoder.Decode(Encoding.UTF8.GetBytes(Antigravity.Replace(from, to)), "agy-1.1.11"));

    [Fact] public async Task PreparedConnectorsStayUnavailableAndCancellable()
    {
        foreach (var plan in PreparedConnections.Plans)
        {
            var connector = new PreparedUsageConnector(plan); var result = await connector.ReadAsync(CancellationToken.None);
            Assert.Equal(IntegrationStage.Prepared, connector.Stage); Assert.False(result.Card.HasDisplayableQuota);
            Assert.Equal(plan.Name, result.Name); Assert.Empty(result.Usage.Days);
            Assert.Throws<OperationCanceledException>(() => { _ = connector.ReadAsync(new CancellationToken(true)); });
        }
        var storage = new PreparedWindowsStorageBackend(); Assert.False(storage.Readiness.InventoryAvailable); Assert.False(storage.Readiness.CanMutate);
    }
}
