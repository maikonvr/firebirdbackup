unit pTesteProcesso;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils, pProcesso;

type
  [TestFixture]
  TTesteProcesso = class
  private
    function Cmd: string;
  public
    [Test] procedure TestCapturaStdoutEExitCode;
    [Test] procedure TestCapturaStderr;
    [Test] procedure TestAmbienteChegaAoFilho;
    [Test] procedure TestExeInexistenteLevantaExcecao;
    [Test] procedure TestSaidaOemConvertida;
    [Test] procedure TestSaidaAnsiSemConversaoPorPadrao;
    [Test] procedure TestTimeoutEncerraProcesso;
    [Test] procedure TestAspas;
  end;

implementation

uses
  Winapi.Windows;

function TTesteProcesso.Cmd: string;
begin
  Result := GetEnvironmentVariable('ComSpec');
end;

procedure TTesteProcesso.TestCapturaStdoutEExitCode;
var
  Linhas: TStringList;
  Codigo: Integer;
begin
  Linhas := TStringList.Create;
  try
    Codigo := ExecutarProcesso(Cmd, '/c "echo um& echo dois& exit 3"', nil,
      procedure(const L: string) begin Linhas.Add(L); end);
    Assert.AreEqual(3, Codigo);
    Assert.AreEqual(2, Linhas.Count);
    Assert.AreEqual('um', Linhas[0]);
    Assert.AreEqual('dois', Linhas[1]);
  finally
    Linhas.Free;
  end;
end;

procedure TTesteProcesso.TestCapturaStderr;
var
  Linhas: TStringList;
begin
  Linhas := TStringList.Create;
  try
    // sem espaço antes do redirecionamento: "echo erro 1>&2" imprimiria "erro "
    ExecutarProcesso(Cmd, '/c "echo erro>&2"', nil,
      procedure(const L: string) begin Linhas.Add(L); end);
    Assert.AreEqual(1, Linhas.Count);
    Assert.AreEqual('erro', Linhas[0]);
  finally
    Linhas.Free;
  end;
end;

procedure TTesteProcesso.TestAmbienteChegaAoFilho;
var
  Linhas, Amb: TStringList;
begin
  Linhas := TStringList.Create;
  Amb := TStringList.Create;
  try
    Amb.Add('ISC_USER=TESTE_USR');
    ExecutarProcesso(Cmd, '/c "echo %ISC_USER%-%ComSpec%"', Amb,
      procedure(const L: string) begin Linhas.Add(L); end);
    Assert.AreEqual(1, Linhas.Count);
    Assert.StartsWith('TESTE_USR-', Linhas[0]);
    Assert.IsFalse(Linhas[0].EndsWith('%ComSpec%'), 'ambiente do pai deve ser herdado');
  finally
    Linhas.Free;
    Amb.Free;
  end;
end;

procedure TTesteProcesso.TestExeInexistenteLevantaExcecao;
begin
  Assert.WillRaise(
    procedure
    begin
      ExecutarProcesso('C:\nao\existe\gbak.exe', '-b', nil, nil);
    end, EProcesso);
end;

procedure TTesteProcesso.TestSaidaOemConvertida;
var
  Linhas: TStringList;
begin
  // cmd.exe/schtasks escrevem na codepage OEM (850/437); com AConverterOem "ção" chega legível.
  Linhas := TStringList.Create;
  try
    ExecutarProcesso(Cmd, '/c "echo ação"', nil,
      procedure(const L: string) begin Linhas.Add(L); end, 0, True);
    Assert.AreEqual('ação', Linhas[0]);
  finally
    Linhas.Free;
  end;
end;

procedure TTesteProcesso.TestSaidaAnsiSemConversaoPorPadrao;
var
  Linhas: TStringList;
  Arq: string;
begin
  // gbak/nbackup escrevem em ANSI (cp1252): por padrão a saída não é convertida.
  // "type" de um arquivo com os bytes cp1252 de "ação" (61 E7 E3 6F) simula isso.
  Arq := TPath.Combine(TPath.GetTempPath, 'fbbk_ansi_' + TPath.GetGUIDFileName + '.txt');
  TFile.WriteAllBytes(Arq, TBytes.Create($61, $E7, $E3, $6F, 13, 10));
  Linhas := TStringList.Create;
  try
    ExecutarProcesso(Cmd, '/c "type ' + Aspas(Arq) + '"', nil,
      procedure(const L: string) begin Linhas.Add(L); end);
    Assert.AreEqual('ação', Linhas[0]);
  finally
    Linhas.Free;
    TFile.Delete(Arq);
  end;
end;

procedure TTesteProcesso.TestTimeoutEncerraProcesso;
var
  Codigo: Integer;
  Inicio: TDateTime;
begin
  // processo que ficaria 30 s vivo deve ser encerrado em ~2 s e retornar CodigoTimeout
  Inicio := Now;
  Codigo := ExecutarProcesso(Cmd, '/c "ping -n 30 127.0.0.1 >nul"', nil, nil, 2000);
  Assert.AreEqual(CodigoTimeout, Codigo);
  Assert.IsTrue((Now - Inicio) * 86400 < 15, 'deveria encerrar perto do timeout');
end;

procedure TTesteProcesso.TestAspas;
begin
  Assert.AreEqual('"C:\Program Files\x.exe"', Aspas('C:\Program Files\x.exe'));
  Assert.AreEqual('""', Aspas(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteProcesso);

end.
