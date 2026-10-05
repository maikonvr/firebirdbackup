unit pTesteBackup;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils, System.IniFiles,
  pConfig, pLog, pBackup;

type
  [TestFixture]
  TTesteBackup = class
  private
    FPasta, FDestino, FFb: string;
    FConfig: TConfig;
    FLog: TLog;
    procedure CriarArquivo(const ANome: string; ADataModif: TDateTime; ATamanho: Integer = 0);
    procedure AddBanco(const ANome: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestNomeArquivoBackup;
    [Test] procedure TestCasaPadraoRetencao;
    [Test] procedure TestRetencaoApagaSoAntigosNoPadrao;
    [Test] procedure TestGravarELerStatus;
  end;

implementation

procedure TTesteBackup.Setup;
begin
  FPasta := TPath.Combine(TPath.GetTempPath, 'fbbk_bk_' + TPath.GetGUIDFileName);
  FDestino := TPath.Combine(FPasta, 'dest');
  FFb := TPath.Combine(FPasta, 'fb');
  TDirectory.CreateDirectory(FDestino);
  TDirectory.CreateDirectory(FFb);
  TFile.WriteAllText(TPath.Combine(FFb, 'gbak.exe'), '');
  TFile.WriteAllText(TPath.Combine(FFb, 'nbackup.exe'), '');
  FConfig := TConfig.Create;
  FConfig.FirebirdDir := FFb;
  FConfig.Destino := FDestino;
  FConfig.Senha := 'segredo';
  FLog := TLog.Create(FDestino);
end;

procedure TTesteBackup.TearDown;
begin
  FLog.Free;
  FConfig.Free;
  TDirectory.Delete(FPasta, True);
end;

procedure TTesteBackup.CriarArquivo(const ANome: string; ADataModif: TDateTime; ATamanho: Integer);
var
  Arq: string;
begin
  Arq := TPath.Combine(FDestino, ANome);
  TFile.WriteAllText(Arq, StringOfChar('x', ATamanho));
  TFile.SetLastWriteTime(Arq, ADataModif);
end;

procedure TTesteBackup.AddBanco(const ANome: string);
var
  B: TBancoConfig;
begin
  B.Nome := ANome;
  B.Arquivo := TPath.Combine(FPasta, ANome + '.FDB');
  TFile.WriteAllText(B.Arquivo, 'db');
  FConfig.Bancos.Add(B);
end;

procedure TTesteBackup.TestNomeArquivoBackup;
begin
  Assert.AreEqual('D:\Bk\AG2006_2026-10-05_0200.fbk',
    TBackup.NomeArquivoBackup('D:\Bk', 'AG2006', EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 7, 0), '.fbk'));
end;

procedure TTesteBackup.TestCasaPadraoRetencao;
var
  Nomes: TArray<string>;
begin
  Nomes := ['AG2006', 'Outro'];
  Assert.IsTrue(TBackup.CasaPadraoRetencao('AG2006_2026-10-05_0200.fbk', Nomes));
  Assert.IsTrue(TBackup.CasaPadraoRetencao('ag2006_2026-10-05_0200.FDB', Nomes));
  Assert.IsTrue(TBackup.CasaPadraoRetencao('backup_2026-10-05.log', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('AG2006.FDB', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('AG2006_2026-10-05_0200.rar', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('XYZ_2026-10-05_0200.fbk', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('AG2006_2026-10-05.fbk', Nomes));
  Assert.IsFalse(TBackup.CasaPadraoRetencao('ultimo-status.ini', Nomes));
end;

procedure TTesteBackup.TestRetencaoApagaSoAntigosNoPadrao;
var
  Bk: TBackup;
  Hoje: TDateTime;
begin
  AddBanco('AG');
  FConfig.RetencaoDias := 7;
  Hoje := EncodeDate(2026, 10, 20);
  CriarArquivo('AG_2026-10-01_0200.fbk', Hoje - 19);    // apaga
  CriarArquivo('AG_2026-10-12_0200.fdb', Hoje - 8);     // apaga
  CriarArquivo('AG_2026-10-14_0200.fbk', Hoje - 6);     // mantém
  CriarArquivo('backup_2026-10-01.log', Hoje - 19);      // apaga
  CriarArquivo('OUTRO_2026-10-01_0200.fbk', Hoje - 19);  // mantém: banco não configurado
  CriarArquivo('importante.txt', Hoje - 30);             // mantém
  Bk := TBackup.Create(FConfig, FLog);
  try
    Bk.Agora := Hoje;
    Bk.AplicarRetencao;
  finally
    Bk.Free;
  end;
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-01_0200.fbk')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-12_0200.fdb')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDestino, 'backup_2026-10-01.log')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'AG_2026-10-14_0200.fbk')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'OUTRO_2026-10-01_0200.fbk')));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FDestino, 'importante.txt')));
end;

procedure TTesteBackup.TestGravarELerStatus;
var
  Bk: TBackup;
  R: TArray<TResultadoBanco>;
  Ini: TIniFile;
begin
  AddBanco('AG');
  SetLength(R, 2);
  R[0].Nome := 'AG'; R[0].Inicio := EncodeDate(2026, 10, 5) + EncodeTime(2, 0, 0, 0);
  R[0].Fim := R[0].Inicio + EncodeTime(0, 1, 30, 0); R[0].OK := True; R[0].Mensagem := '';
  R[0].TamanhoFbk := 1234; R[0].TamanhoFdb := 5678;
  R[1].Nome := 'XY'; R[1].Inicio := R[0].Fim; R[1].Fim := R[0].Fim; R[1].OK := False;
  R[1].Mensagem := 'falhou';
  Bk := TBackup.Create(FConfig, FLog);
  try
    Bk.Agora := R[0].Inicio;
    Bk.GravarStatus(R);
  finally
    Bk.Free;
  end;
  Ini := TIniFile.Create(TPath.Combine(FDestino, 'ultimo-status.ini'));
  try
    Assert.AreEqual('ERRO', Ini.ReadString('Geral', 'Resultado', ''));
    Assert.AreEqual('2026-10-05 02:00:00', Ini.ReadString('Geral', 'UltimaExecucao', ''));
    Assert.AreEqual('OK', Ini.ReadString('AG', 'Resultado', ''));
    Assert.AreEqual(90, Ini.ReadInteger('AG', 'DuracaoSeg', -1));
    Assert.AreEqual('1234', Ini.ReadString('AG', 'TamanhoFbk', ''));
    Assert.AreEqual('falhou', Ini.ReadString('XY', 'Mensagem', ''));
  finally
    Ini.Free;
  end;
  Assert.AreEqual(R[0].Inicio, TBackup.LerUltimaExecucao(FDestino), 0.00001);
  Assert.AreEqual(0.0, TBackup.LerUltimaExecucao(TPath.Combine(FPasta, 'vazio')), 0.00001);
end;

initialization
  TDUnitX.RegisterTestFixture(TTesteBackup);

end.
