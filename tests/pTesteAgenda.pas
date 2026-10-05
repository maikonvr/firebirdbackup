unit pTesteAgenda;

interface

uses
  DUnitX.TestFramework, System.SysUtils, pAgenda;

type
  [TestFixture]
  TTesteAgenda = class
  public
    [Test] procedure TestNaoDisparaAntesDoHorario;
    [Test] procedure TestDisparaNoHorario;
    [Test] procedure TestDisparaAtrasadoUmaVez;
    [Test] procedure TestNaoDisparaSeJaRodouHoje;
    [Test] procedure TestDisparaSeUltimaFoiOntem;
    [Test] procedure TestComandoSchtasks;
  end;

implementation

procedure TTesteAgenda.TestNaoDisparaAntesDoHorario;
begin
  Assert.IsFalse(DeveDisparar(EncodeDate(2026, 10, 5) + EncodeTime(1, 59, 0, 0), '02:00', 0));
end;

procedure TTesteAgenda.TestDisparaNoHorario;
begin
  Assert.IsTrue(DeveDisparar(EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 0, 0), '02:00', 0));
end;

procedure TTesteAgenda.TestDisparaAtrasadoUmaVez;
begin
  Assert.IsTrue(DeveDisparar(EncodeDate(2026, 10, 5) + EncodeTime(10, 0, 0, 0), '02:00',
    EncodeDate(2026, 10, 4) + EncodeTime(2, 0, 0, 0)));
end;

procedure TTesteAgenda.TestNaoDisparaSeJaRodouHoje;
begin
  Assert.IsFalse(DeveDisparar(EncodeDate(2026, 10, 5) + EncodeTime(10, 0, 0, 0), '02:00',
    EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 30, 0)));
end;

procedure TTesteAgenda.TestDisparaSeUltimaFoiOntem;
begin
  Assert.IsTrue(DeveDisparar(EncodeDate(2026, 10, 5) + EncodeTime(2, 1, 0, 0), '02:00',
    EncodeDate(2026, 10, 4) + EncodeTime(23, 59, 0, 0)));
end;

procedure TTesteAgenda.TestComandoSchtasks;
begin
  Assert.AreEqual(
    '/Create /F /SC DAILY /TN FirebirdBackup /TR "\"C:\Program Files\Bk\FirebirdBackup.exe\" --run" /ST 02:00 /RU SYSTEM /RL HIGHEST',
    ArgumentosSchtasks('C:\Program Files\Bk\FirebirdBackup.exe', '02:00'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteAgenda);

end.
