using System.Collections.Concurrent;
using BarIceCreamShop.Api.Models;

namespace BarIceCreamShop.Api.Services;

/// Lo que la API recuerda en memoria de cada agente de impresión. El agente pregunta todo el día
/// si hay algo para imprimir; con esto, cuando no hay trabajos, esas preguntas no tocan la base.
public sealed class PrintAgentState
{
    // Una vez por hora, en la primera consulta después de la hora en punto (HourlyCheck), se vuelve a
    // leer el agente de la base, se guarda su último contacto y se revisa la cola aunque no haya avisos.
    // Todos los agentes lo hacen en el mismo medio minuto: la base se despierta una sola vez por hora.
    private static bool SameHour(DateTime a, DateTime b) => HourlyCheck.Slot(a) == HourlyCheck.Slot(b);

    public sealed record Snapshot(int Id, int IdEmpresa, int IdSucursal, string Nombre, string? Equipo, DateTime LoadedAt);

    private readonly ConcurrentDictionary<string, Snapshot> _byHash = new();
    private readonly ConcurrentDictionary<int, DateTime> _lastSeen = new();
    private readonly ConcurrentDictionary<int, (long Version, DateTime At)> _checked = new();
    private readonly ConcurrentDictionary<string, DateTime> _invalid = new();

    public Snapshot? Find(string hash, DateTime now) =>
        _byHash.TryGetValue(hash, out var value) && SameHour(now, value.LoadedAt) ? value : null;

    /// Claves que no existen: un agente con clave vieja reintenta cada 30 s y no debe despertar la base.
    public bool IsInvalid(string hash, DateTime now) => _invalid.TryGetValue(hash, out var at) && SameHour(now, at);

    public void Invalid(string hash, DateTime now) => _invalid[hash] = now;

    public Snapshot Remember(string hash, PrintAgent agent, DateTime now)
    {
        Forget(agent.Id, clearSeen: false);
        var snapshot = new Snapshot(agent.Id, agent.IdEmpresa, agent.IdSucursal, agent.Nombre, agent.Equipo, now);
        _byHash[hash] = snapshot;
        return snapshot;
    }

    /// Al renombrar, borrar o cambiar la clave de un agente: se vuelve a leer de la base.
    public void Forget(int agentId, bool clearSeen)
    {
        foreach (var item in _byHash.Where(x => x.Value.Id == agentId).ToList())
            _byHash.TryRemove(item.Key, out _);
        _checked.TryRemove(agentId, out _);
        if (clearSeen) _lastSeen.TryRemove(agentId, out _);
    }

    public void Seen(int agentId, DateTime now) => _lastSeen[agentId] = now;

    public DateTime? LastSeen(int agentId) => _lastSeen.TryGetValue(agentId, out var value) ? value : null;

    /// Hay que consultar la cola si llegó un aviso desde la última revisión, o si pasó el tiempo de resguardo.
    public bool NeedsCheck(int agentId, long version, DateTime now) =>
        !_checked.TryGetValue(agentId, out var last) || last.Version != version || !SameHour(now, last.At);

    public void Checked(int agentId, long version, DateTime now) => _checked[agentId] = (version, now);
}
