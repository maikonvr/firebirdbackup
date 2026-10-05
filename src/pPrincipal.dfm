object FormPrincipal: TFormPrincipal
  Left = 0
  Top = 0
  Caption = 'Backup Firebird'
  ClientHeight = 600
  ClientWidth = 780
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object gbFirebird: TGroupBox
    Left = 8
    Top = 8
    Width = 380
    Height = 120
    Caption = ' Firebird '
    TabOrder = 0
    object lblFirebirdDir: TLabel
      Left = 12
      Top = 24
      Width = 100
      Height = 15
      Caption = 'Pasta do Firebird:'
    end
    object lblUsuario: TLabel
      Left = 12
      Top = 84
      Width = 44
      Height = 15
      Caption = 'Usu'#225'rio:'
    end
    object lblSenha: TLabel
      Left = 196
      Top = 84
      Width = 37
      Height = 15
      Caption = 'Senha:'
    end
    object edtFirebirdDir: TEdit
      Left = 12
      Top = 44
      Width = 320
      Height = 23
      TabOrder = 0
    end
    object btnFirebirdDir: TButton
      Left = 336
      Top = 43
      Width = 32
      Height = 25
      Caption = '...'
      TabOrder = 1
      OnClick = btnFirebirdDirClick
    end
    object edtUsuario: TEdit
      Left = 68
      Top = 80
      Width = 116
      Height = 23
      TabOrder = 2
    end
    object edtSenha: TEdit
      Left = 240
      Top = 80
      Width = 128
      Height = 23
      PasswordChar = '*'
      TabOrder = 3
    end
  end
  object gbDestino: TGroupBox
    Left = 396
    Top = 8
    Width = 376
    Height = 120
    Caption = ' Destino e rotina '
    TabOrder = 1
    object lblDestino: TLabel
      Left = 12
      Top = 24
      Width = 86
      Height = 15
      Caption = 'Pasta de destino:'
    end
    object lblRetencao: TLabel
      Left = 12
      Top = 84
      Width = 90
      Height = 15
      Caption = 'Manter por (dias):'
    end
    object lblHorario: TLabel
      Left = 164
      Top = 84
      Width = 44
      Height = 15
      Caption = 'Hor'#225'rio:'
    end
    object edtDestino: TEdit
      Left = 12
      Top = 44
      Width = 316
      Height = 23
      TabOrder = 0
    end
    object btnDestino: TButton
      Left = 332
      Top = 43
      Width = 32
      Height = 25
      Caption = '...'
      TabOrder = 1
      OnClick = btnDestinoClick
    end
    object edtRetencao: TEdit
      Left = 108
      Top = 80
      Width = 40
      Height = 23
      NumbersOnly = True
      TabOrder = 2
      Text = '7'
    end
    object edtHorario: TMaskEdit
      Left = 214
      Top = 80
      Width = 50
      Height = 23
      EditMask = '!90:00;1;_'
      MaxLength = 5
      TabOrder = 3
      Text = '02:00'
    end
    object chkFbk: TCheckBox
      Left = 276
      Top = 70
      Width = 90
      Height = 17
      Caption = 'C'#243'pia .fbk'
      Checked = True
      State = cbChecked
      TabOrder = 4
    end
    object chkFdb: TCheckBox
      Left = 276
      Top = 92
      Width = 90
      Height = 17
      Caption = 'C'#243'pia .fdb'
      Checked = True
      State = cbChecked
      TabOrder = 5
    end
  end
  object gbBancos: TGroupBox
    Left = 8
    Top = 136
    Width = 764
    Height = 150
    Caption = ' Bancos '
    TabOrder = 2
    object lvBancos: TListView
      Left = 12
      Top = 24
      Width = 640
      Height = 112
      Columns = <
        item
          Caption = 'Nome'
          Width = 140
        end
        item
          Caption = 'Arquivo'
          Width = 480
        end>
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
    end
    object btnAdicionar: TButton
      Left = 660
      Top = 24
      Width = 92
      Height = 25
      Caption = 'Adicionar...'
      TabOrder = 1
      OnClick = btnAdicionarClick
    end
    object btnEditar: TButton
      Left = 660
      Top = 55
      Width = 92
      Height = 25
      Caption = 'Editar...'
      TabOrder = 2
      OnClick = btnEditarClick
    end
    object btnRemover: TButton
      Left = 660
      Top = 86
      Width = 92
      Height = 25
      Caption = 'Remover'
      TabOrder = 3
      OnClick = btnRemoverClick
    end
  end
  object pnlBotoes: TPanel
    Left = 8
    Top = 294
    Width = 764
    Height = 40
    BevelOuter = bvNone
    TabOrder = 3
    object btnSalvar: TButton
      Left = 0
      Top = 6
      Width = 110
      Height = 28
      Caption = 'Salvar'
      TabOrder = 0
      OnClick = btnSalvarClick
    end
    object btnAgendar: TButton
      Left = 116
      Top = 6
      Width = 150
      Height = 28
      Caption = 'Agendar no Windows'
      TabOrder = 1
      OnClick = btnAgendarClick
    end
    object btnExecutar: TButton
      Left = 272
      Top = 6
      Width = 130
      Height = 28
      Caption = 'Executar agora'
      TabOrder = 2
      OnClick = btnExecutarClick
    end
    object pbAndamento: TProgressBar
      Left = 412
      Top = 10
      Width = 340
      Height = 20
      Style = pbstMarquee
      TabOrder = 3
      Visible = False
    end
  end
  object gbUltimo: TGroupBox
    Left = 8
    Top = 340
    Width = 764
    Height = 92
    Caption = ' '#218'ltimo backup '
    TabOrder = 4
    object lvUltimo: TListView
      Left = 12
      Top = 22
      Width = 740
      Height = 60
      Columns = <
        item
          Caption = 'Banco'
          Width = 110
        end
        item
          Caption = 'In'#237'cio'
          Width = 130
        end
        item
          Caption = 'Dura'#231#227'o'
          Width = 70
        end
        item
          Caption = 'Resultado'
          Width = 70
        end
        item
          Caption = '.fbk (MB)'
          Width = 70
        end
        item
          Caption = '.fdb (MB)'
          Width = 70
        end
        item
          Caption = 'Mensagem'
          Width = 200
        end>
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
    end
  end
  object memoLog: TMemo
    Left = 8
    Top = 440
    Width = 764
    Height = 152
    Font.Charset = ANSI_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 5
  end
  object TrayIcon: TTrayIcon
    PopupMenu = pmTray
    Visible = True
    OnDblClick = miAbrirClick
    Left = 712
    Top = 296
  end
  object pmTray: TPopupMenu
    Left = 744
    Top = 296
    object miAbrir: TMenuItem
      Caption = 'Abrir'
      Default = True
      OnClick = miAbrirClick
    end
    object miExecutar: TMenuItem
      Caption = 'Executar agora'
      OnClick = btnExecutarClick
    end
    object miSep: TMenuItem
      Caption = '-'
    end
    object miSair: TMenuItem
      Caption = 'Sair'
      OnClick = miSairClick
    end
  end
  object Timer: TTimer
    Interval = 60000
    OnTimer = TimerTimer
    Left = 680
    Top = 296
  end
end
