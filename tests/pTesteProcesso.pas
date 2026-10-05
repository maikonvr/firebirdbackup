unit pTesteProcesso;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, pProcesso;

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
  // cmd.exe escreve na codepage OEM (850/437); "ção" precisa chegar legível.
  Linhas := TStringList.Create;
  try
    ExecutarProcesso(Cmd, '/c "echo ação"', nil,
      procedure(const L: string) begin Linhas.Add(L); end);
    Assert.AreEqual('ação', Linhas[0]);
  finally
    Linhas.Free;
  end;
end;

procedure TTesteProcesso.TestAspas;
begin
  Assert.AreEqual('"C:\Program Files\x.exe"', Aspas('C:\Program Files\x.exe'));
  Assert.AreEqual('""', Aspas(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteProcesso);

end.
