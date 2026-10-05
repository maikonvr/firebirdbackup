unit pPrincipal;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.IniFiles,
  System.UITypes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Mask,
  Vcl.Dialogs, Vcl.FileCtrl,
  pConfig, pLog, pBackup;

type
  TFormPrincipal = class(TForm)
    gbFirebird: TGroupBox;
    lblFirebirdDir: TLabel;
    lblUsuario: TLabel;
    lblSenha: TLabel;
    edtFirebirdDir: TEdit;
    btnFirebirdDir: TButton;
    edtUsuario: TEdit;
    edtSenha: TEdit;
    gbDestino: TGroupBox;
    lblDestino: TLabel;
    lblRetencao: TLabel;
    lblHorario: TLabel;
    edtDestino: TEdit;
    btnDestino: TButton;
    edtRetencao: TEdit;
    edtHorario: TMaskEdit;
    chkFbk: TCheckBox;
    chkFdb: TCheckBox;
    gbBancos: TGroupBox;
    lvBancos: TListView;
    btnAdicionar: TButton;
    btnEditar: TButton;
    btnRemover: TButton;
    pnlBotoes: TPanel;
    btnSalvar: TButton;
    btnAgendar: TButton;
    btnExecutar: TButton;
    pbAndamento: TProgressBar;
    gbUltimo: TGroupBox;
    lvUltimo: TListView;
    memoLog: TMemo;
    TrayIcon: TTrayIcon;
    pmTray: TPopupMenu;
    miAbrir: TMenuItem;
    miExecutar: TMenuItem;
    miSep: TMenuItem;
    miSair: TMenuItem;
    Timer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure btnFirebirdDirClick(Sender: TObject);
    procedure btnDestinoClick(Sender: TObject);
    procedure btnAdicionarClick(Sender: TObject);
    procedure btnEditarClick(Sender: TObject);
    procedure btnRemoverClick(Sender: TObject);
    procedure btnSalvarClick(Sender: TObject);
    procedure btnAgendarClick(Sender: TObject);
    procedure btnExecutarClick(Sender: TObject);
    procedure miAbrirClick(Sender: TObject);
    procedure miSairClick(Sender: TObject);
    procedure TimerTimer(Sender: TObject);
  private
    FConfig: TConfig;
    FExecutando: Boolean;
    FSair: Boolean;
    procedure ConfigParaTela;
    function TelaParaConfig(out AErro: string): Boolean;
    procedure PreencherBancos;
    procedure CarregarUltimoStatus;
    function EditarBanco(var ABanco: TBancoConfig): Boolean;
    function CopiarConfig(AOrigem: TConfig): TConfig;
    // AConfig: cópia que passa a pertencer à thread (liberada por ela)
    procedure IniciarBackup(const AOrigem: string; AConfig: TConfig);
    procedure AoTerminar(AOk: Boolean);
    procedure Habilitar(AAtivo: Boolean);
    procedure LimitarMemo;
  protected
    procedure WndProc(var Message: TMessage); override;
  end;

var
  FormPrincipal: TFormPrincipal;

// Mensagem registrada que uma segunda instância envia para a janela existente se mostrar.
// (ShowWindow de fora não atualiza Visible do form, e o Hide seguinte não funcionaria.)
function MensagemAbrir: UINT;

implementation

uses
  System.IOUtils, pAgenda;

{$R *.dfm}

const
  MaxLinhasMemo = 5000;
  LinhasRemovidas = 1000;

var
  MsgAbrir: UINT = 0;

function MensagemAbrir: UINT;
begin
  if MsgAbrir = 0 then
    MsgAbrir := RegisterWindowMessage('FirebirdBackup_Abrir');
  Result := MsgAbrir;
end;

procedure TFormPrincipal.WndProc(var Message: TMessage);
begin
  if (Message.Msg = MensagemAbrir) and (Message.Msg <> 0) then
    miAbrirClick(nil)
  else
    inherited;
end;

procedure TFormPrincipal.FormCreate(Sender: TObject);
begin
  FConfig := TConfig.Create;
  if TFile.Exists(TConfig.ArquivoPadrao) then
    FConfig.Carregar(TConfig.ArquivoPadrao);
  ConfigParaTela;
  CarregarUltimoStatus;
  TrayIcon.Hint := Application.Title;
  TrayIcon.Icon := Application.Icon;
end;

procedure TFormPrincipal.FormDestroy(Sender: TObject);
begin
  FConfig.Free;
end;

procedure TFormPrincipal.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FSair then
  begin
    CanClose := not FExecutando or
      (MessageDlg('Há um backup em andamento. Sair mesmo assim?', mtWarning, [mbYes, mbNo], 0) = mrYes);
    Exit;
  end;
  CanClose := False;
  Hide;
  TrayIcon.BalloonTitle := Application.Title;
  TrayIcon.BalloonHint := 'Continua rodando aqui. Clique duas vezes para abrir.';
  TrayIcon.BalloonFlags := bfInfo;
  TrayIcon.ShowBalloonHint;
end;

procedure TFormPrincipal.ConfigParaTela;
begin
  edtFirebirdDir.Text := FConfig.FirebirdDir;
  edtUsuario.Text := FConfig.Usuario;
  edtSenha.Text := FConfig.Senha;
  edtDestino.Text := FConfig.Destino;
  edtRetencao.Text := IntToStr(FConfig.RetencaoDias);
  edtHorario.Text := FConfig.Horario;
  chkFbk.Checked := FConfig.CopiaFbk;
  chkFdb.Checked := FConfig.CopiaFdb;
  PreencherBancos;
end;

function TFormPrincipal.TelaParaConfig(out AErro: string): Boolean;
begin
  FConfig.FirebirdDir := Trim(edtFirebirdDir.Text);
  FConfig.Usuario := Trim(edtUsuario.Text);
  FConfig.Senha := edtSenha.Text;
  FConfig.Destino := Trim(edtDestino.Text);
  FConfig.RetencaoDias := StrToIntDef(edtRetencao.Text, 0);
  FConfig.Horario := Trim(edtHorario.Text);
  FConfig.CopiaFbk := chkFbk.Checked;
  FConfig.CopiaFdb := chkFdb.Checked;
  Result := FConfig.Validar(AErro);
end;

procedure TFormPrincipal.PreencherBancos;
var
  B: TBancoConfig;
  Item: TListItem;
begin
  lvBancos.Items.BeginUpdate;
  try
    lvBancos.Items.Clear;
    for B in FConfig.Bancos do
    begin
      Item := lvBancos.Items.Add;
      Item.Caption := B.Nome;
      Item.SubItems.Add(B.Arquivo);
    end;
  finally
    lvBancos.Items.EndUpdate;
  end;
end;

function MB(const S: string): string;
begin
  Result := FormatFloat('0.0', StrToInt64Def(S, 0) / 1048576);
end;

procedure TFormPrincipal.CarregarUltimoStatus;
var
  Ini: TIniFile;
  B: TBancoConfig;
  Item: TListItem;
  Arq: string;
begin
  lvUltimo.Items.Clear;
  Arq := TPath.Combine(FConfig.Destino, 'ultimo-status.ini');
  if (FConfig.Destino = '') or not TFile.Exists(Arq) then
    Exit;
  Ini := TIniFile.Create(Arq);
  try
    for B in FConfig.Bancos do
      if Ini.SectionExists(B.Nome) then
      begin
        Item := lvUltimo.Items.Add;
        Item.Caption := B.Nome;
        Item.SubItems.Add(Ini.ReadString(B.Nome, 'Inicio', ''));
        Item.SubItems.Add(Ini.ReadString(B.Nome, 'DuracaoSeg', '') + ' s');
        Item.SubItems.Add(Ini.ReadString(B.Nome, 'Resultado', ''));
        Item.SubItems.Add(MB(Ini.ReadString(B.Nome, 'TamanhoFbk', '0')));
        Item.SubItems.Add(MB(Ini.ReadString(B.Nome, 'TamanhoFdb', '0')));
        Item.SubItems.Add(Ini.ReadString(B.Nome, 'Mensagem', ''));
      end;
  finally
    Ini.Free;
  end;
end;

procedure TFormPrincipal.btnFirebirdDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := edtFirebirdDir.Text;
  if SelectDirectory('Pasta do Firebird (onde estão gbak.exe e nbackup.exe)', '', Dir,
    [sdNewUI], Self) then
    edtFirebirdDir.Text := Dir;
end;

procedure TFormPrincipal.btnDestinoClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := edtDestino.Text;
  if SelectDirectory('Pasta de destino dos backups', '', Dir, [sdNewUI, sdNewFolder], Self) then
    edtDestino.Text := Dir;
end;

function TFormPrincipal.EditarBanco(var ABanco: TBancoConfig): Boolean;
var
  Nome: string;
  Dlg: TOpenDialog;
begin
  Result := False;
  Nome := ABanco.Nome;
  if not InputQuery('Banco', 'Nome (só letras, dígitos, - e _):', Nome) then
    Exit;
  if not TConfig.NomeValido(Trim(Nome)) then
  begin
    MessageDlg('Nome inválido.', mtError, [mbOK], 0);
    Exit;
  end;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Arquivo do banco (.FDB)';
    Dlg.Filter := 'Banco Firebird (*.fdb;*.gdb)|*.fdb;*.gdb|Todos (*.*)|*.*';
    Dlg.FileName := ABanco.Arquivo;
    Dlg.Options := [ofFileMustExist, ofHideReadOnly];
    if not Dlg.Execute(Handle) then
      Exit;
    ABanco.Nome := Trim(Nome);
    ABanco.Arquivo := Dlg.FileName;
    Result := True;
  finally
    Dlg.Free;
  end;
end;

procedure TFormPrincipal.btnAdicionarClick(Sender: TObject);
var
  B: TBancoConfig;
begin
  B := Default(TBancoConfig);
  if EditarBanco(B) then
  begin
    FConfig.Bancos.Add(B);
    PreencherBancos;
  end;
end;

procedure TFormPrincipal.btnEditarClick(Sender: TObject);
var
  B: TBancoConfig;
  I: Integer;
begin
  if lvBancos.ItemIndex < 0 then
    Exit;
  I := lvBancos.ItemIndex;
  B := FConfig.Bancos[I];
  if EditarBanco(B) then
  begin
    FConfig.Bancos[I] := B;
    PreencherBancos;
  end;
end;

procedure TFormPrincipal.btnRemoverClick(Sender: TObject);
begin
  if lvBancos.ItemIndex < 0 then
    Exit;
  FConfig.Bancos.Delete(lvBancos.ItemIndex);
  PreencherBancos;
end;

procedure TFormPrincipal.btnSalvarClick(Sender: TObject);
var
  Erro: string;
begin
  if not TelaParaConfig(Erro) then
  begin
    MessageDlg(Erro, mtError, [mbOK], 0);
    Exit;
  end;
  FConfig.Salvar(TConfig.ArquivoPadrao);
  CarregarUltimoStatus;
  MessageDlg('Configuração salva.', mtInformation, [mbOK], 0);
end;

procedure TFormPrincipal.btnAgendarClick(Sender: TObject);
var
  Erro, Saida: string;
begin
  if not TelaParaConfig(Erro) then
  begin
    MessageDlg(Erro, mtError, [mbOK], 0);
    Exit;
  end;
  FConfig.Salvar(TConfig.ArquivoPadrao);
  if AgendarTarefa(ParamStr(0), FConfig.Horario, Saida) then
    MessageDlg('Tarefa "FirebirdBackup" agendada todo dia às ' + FConfig.Horario + '.' + sLineBreak + Saida,
      mtInformation, [mbOK], 0)
  else
    MessageDlg('Não foi possível agendar (execute como administrador).' + sLineBreak + Saida,
      mtError, [mbOK], 0);
end;

procedure TFormPrincipal.Habilitar(AAtivo: Boolean);
begin
  btnSalvar.Enabled := AAtivo;
  btnAgendar.Enabled := AAtivo;
  btnExecutar.Enabled := AAtivo;
  miExecutar.Enabled := AAtivo;
  btnAdicionar.Enabled := AAtivo;
  btnEditar.Enabled := AAtivo;
  btnRemover.Enabled := AAtivo;
  pbAndamento.Visible := not AAtivo;
end;

procedure TFormPrincipal.LimitarMemo;
var
  I: Integer;
begin
  if memoLog.Lines.Count <= MaxLinhasMemo then
    Exit;
  memoLog.Lines.BeginUpdate;
  try
    for I := 1 to LinhasRemovidas do
      memoLog.Lines.Delete(0);
  finally
    memoLog.Lines.EndUpdate;
  end;
end;

function TFormPrincipal.CopiarConfig(AOrigem: TConfig): TConfig;
var
  B: TBancoConfig;
begin
  Result := TConfig.Create;
  Result.FirebirdDir := AOrigem.FirebirdDir; Result.Usuario := AOrigem.Usuario;
  Result.Senha := AOrigem.Senha; Result.Destino := AOrigem.Destino;
  Result.RetencaoDias := AOrigem.RetencaoDias; Result.Horario := AOrigem.Horario;
  Result.CopiaFbk := AOrigem.CopiaFbk; Result.CopiaFdb := AOrigem.CopiaFdb;
  for B in AOrigem.Bancos do
    Result.Bancos.Add(B);
end;

procedure TFormPrincipal.IniciarBackup(const AOrigem: string; AConfig: TConfig);
var
  Config: TConfig;
begin
  Config := AConfig;
  if FExecutando then
  begin
    memoLog.Lines.Add('Pedido (' + AOrigem + ') ignorado: backup já em andamento nesta janela');
    Config.Free;
    Exit;
  end;
  if TBackup.OutroEmAndamento then
  begin
    memoLog.Lines.Add('Pedido (' + AOrigem + ') ignorado: backup já em andamento em outro processo (tarefa agendada?)');
    Config.Free;
    Exit;
  end;
  FExecutando := True;
  Habilitar(False);
  memoLog.Lines.Add('--- Backup iniciado (' + AOrigem + ')');
  TThread.CreateAnonymousThread(
    procedure
    var
      Log: TLog;
      Backup: TBackup;
      Ok: Boolean;
    begin
      Ok := False;
      try
        try
          Log := TLog.Create(Config.Destino);
          try
            Log.OnLinha := procedure(const L: string)
              begin
                TThread.Queue(nil, procedure
                  begin
                    memoLog.Lines.Add(L);
                    LimitarMemo;
                  end);
              end;
            Backup := TBackup.Create(Config, Log);
            try
              Ok := Backup.Executar;
            finally
              Backup.Free;
            end;
          finally
            Log.Free;
          end;
        except
          on E: Exception do
          begin
            Ok := False;
            TThread.Queue(nil, procedure
              begin
                memoLog.Lines.Add('ERRO fatal: ' + E.ClassName + ': ' + E.Message);
              end);
          end;
        end;
      finally
        Config.Free;
        TThread.Queue(nil, procedure begin AoTerminar(Ok); end);
      end;
    end).Start;
end;

procedure TFormPrincipal.AoTerminar(AOk: Boolean);
begin
  FExecutando := False;
  Habilitar(True);
  LimitarMemo;
  CarregarUltimoStatus;
  if not AOk then
  begin
    TrayIcon.BalloonTitle := 'Backup Firebird';
    TrayIcon.BalloonHint := 'O backup terminou com ERRO. Veja o log.';
    TrayIcon.BalloonFlags := bfError;
    TrayIcon.ShowBalloonHint;
  end;
end;

// Executar agora usa o que está na tela e salva, como o botão Salvar faria.
procedure TFormPrincipal.btnExecutarClick(Sender: TObject);
var
  Erro: string;
begin
  if FExecutando then
  begin
    memoLog.Lines.Add('Pedido (manual) ignorado: backup já em andamento nesta janela');
    Exit;
  end;
  if not TelaParaConfig(Erro) then
  begin
    memoLog.Lines.Add('Configuração inválida: ' + Erro);
    MessageDlg(Erro, mtError, [mbOK], 0);
    Exit;
  end;
  FConfig.Salvar(TConfig.ArquivoPadrao);
  IniciarBackup('manual', CopiarConfig(FConfig));
end;

// O timer só considera a configuração SALVA (backup.ini): o que está sendo digitado na
// tela não entra, e nada é gravado sem o usuário clicar em Salvar.
procedure TFormPrincipal.TimerTimer(Sender: TObject);
var
  Salva: TConfig;
  Erro: string;
begin
  if FExecutando or not TFile.Exists(TConfig.ArquivoPadrao) then
    Exit;
  Salva := TConfig.Create;
  try
    Salva.Carregar(TConfig.ArquivoPadrao);
    if not TConfig.HorarioValido(Salva.Horario) or (Salva.Destino = '') then
      Exit;
    if not DeveDisparar(Now, Salva.Horario, TBackup.LerUltimaExecucao(Salva.Destino)) then
      Exit;
    if not Salva.Validar(Erro) then
    begin
      memoLog.Lines.Add('Timer: configuração salva inválida: ' + Erro);
      Exit;
    end;
  except
    Salva.Free;
    raise;
  end;
  IniciarBackup('timer', Salva);
end;

procedure TFormPrincipal.miAbrirClick(Sender: TObject);
begin
  Show;
  WindowState := wsNormal;
  Application.BringToFront;
end;

procedure TFormPrincipal.miSairClick(Sender: TObject);
begin
  FSair := True;
  Close;
end;

end.
