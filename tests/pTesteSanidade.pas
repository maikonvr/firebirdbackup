unit pTesteSanidade;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTesteSanidade = class
  public
    [Test]
    procedure TestAmbienteCompila;
  end;

implementation

procedure TTesteSanidade.TestAmbienteCompila;
begin
  Assert.AreEqual(2, 1 + 1);
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteSanidade);

end.
