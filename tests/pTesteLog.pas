unit pTesteLog;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, System.Classes, pLog;

type
  [TestFixture]
  TTesteLog = class
  private
    FPasta: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestNomeArquivoPorDia;
    [Test] procedure TestEscreverGravaEDispara;
    [Test] procedure TestEscreverAcumulaLinhas;
  end;

implementation

procedure TTesteLog.Setup;
begin
  FPasta := TPath.Combine(TPath.GetTempPath, 'fbbk_log_' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(FPasta);
end;

procedure TTesteLog.TearDown;
begin
  TDirectory.Delete(FPasta, True);
end;

procedure TTesteLog.TestNomeArquivoPorDia;
begin
  Assert.AreEqual(TPath.Combine('D:\Bk', 'backup_2026-10-05.log'),
    TLog.NomeArquivo('D:\Bk', EncodeDate(2026, 10, 5)));
end;

procedure TTesteLog.TestEscreverGravaEDispara;
var
  L: TLog;
  Recebida: string;
  Conteudo: string;
begin
  L := TLog.Create(FPasta);
  try
    L.Agora := EncodeDate(2026, 10, 5) + EncodeTime(2, 3, 4, 0);
    L.OnLinha := procedure(const ALinha: string) begin Recebida := ALinha; end;
    L.Escrever('Olá');
    Assert.AreEqual('02:03:04  Olá', Recebida);
    Conteudo := TFile.ReadAllText(TLog.NomeArquivo(FPasta, EncodeDate(2026, 10, 5)), TEncoding.UTF8);
    Assert.AreEqual('02:03:04  Olá' + sLineBreak, Conteudo);
  finally
    L.Free;
  end;
end;

procedure TTesteLog.TestEscreverAcumulaLinhas;
var
  L: TLog;
  Linhas: TArray<string>;
begin
  L := TLog.Create(FPasta);
  try
    L.Agora := EncodeDate(2026, 10, 5);
    L.Escrever('a');
    L.Escrever('b');
    Linhas := TFile.ReadAllLines(TLog.NomeArquivo(FPasta, EncodeDate(2026, 10, 5)), TEncoding.UTF8);
    Assert.AreEqual(2, Length(Linhas));
    Assert.EndsWith('b', Linhas[1]);
  finally
    L.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteLog);

end.
