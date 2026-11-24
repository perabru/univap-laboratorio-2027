# OneClick — Laboratório UNIVAP 2027

Aplicativo Windows com interface em português para preparar Arduino, ESP32 e Raspberry Pi Pico. Inspirado no fluxo de [perabru/OneClickInstallerEspRasp](https://github.com/perabru/OneClickInstallerEspRasp), reimplementado com registro de erros, seleção de componentes e preservação da configuração. As cores acompanham o portal didático; este aplicativo não é um produto oficial da universidade.

## Uso

1. Use Windows 10/11 x64 Intel/AMD, internet e uma conta de administrador. Feche o Arduino IDE.
2. Execute `OneClick-UNIVAP-Setup.exe`, selecione os componentes e clique em **Instalar selecionados**.
3. Aguarde o resultado. Em caso de falha, consulte o log e tente novamente apenas os itens necessários.
4. Abra o Arduino IDE, escolha a placa e teste um exemplo com o hardware conectado.

O executável solicita elevação desde a abertura, pois inclui instalação de drivers. **As ferramentas, bibliotecas e configuração pertencem à conta Windows que executa o processo elevado. Se o UAC pedir credenciais de outra conta de administrador, será preparado o perfil dessa outra conta — não o perfil do aluno.** Para laboratórios com alunos sem privilégios administrativos, a equipe de TI deve planejar a preparação de cada perfil e o provisionamento dos drivers. O instalador não tenta obter credenciais nem modificar outros perfis.

## Componentes

- Arduino IDE e Arduino CLI: última versão estável publicada pelos projetos oficiais no momento da execução.
- Pacotes de placas: `esp32:esp32`, `rp2040:rp2040` (Earle Philhower) e `arduino:mbed_rp2040`.
- Drivers USB: Silicon Labs CP210x, WCH CH340/CH341 e FTDI VCP.
- Bibliotecas do Library Manager: DHT sensor library, Adafruit Unified Sensor, PubSubClient, ArduinoJson, LiquidCrystal I2C e Servo, com dependências resolvidas pelo Arduino CLI.

“Bibliotecas didáticas” é esse conjunto específico; não significa todas as bibliotecas disponíveis. A compatibilidade de cada biblioteca depende da placa e do sketch. Os programas gerais de redes, banco de dados e desenvolvimento Android são disponibilizados por links no portal e não são instalados por este executável.

## Configuração, downloads e diagnóstico

O CLI fica em `%LOCALAPPDATA%\OneClick-UNIVAP\tools`. A configuração usada por CLI e Arduino IDE 2 é `%USERPROFILE%\.arduinoIDE\arduino-cli.yaml`. O arquivo existente é copiado para um backup datado; as alterações são aplicadas em uma cópia e só substituem o arquivo original depois de concluídas. Não é executado `config init --overwrite`, não se apaga o sketchbook e não se alteram configurações legadas de forma indiscriminada. Preferências reconhecidas pelo CLI são mantidas. A configuração anterior permanece no arquivo `.bak` ao lado do original.

Downloads usam HTTPS e são repetidos até três vezes. Quando a API do GitHub publica o digest, o SHA-256 é comparado. O instalador Arduino precisa ter assinatura Authenticode válida. Drivers são extraídos como INF/CAT; os catálogos precisam ter assinatura válida e o PnPUtil valida os pacotes antes de adicioná-los ao Windows. Nenhum EXE encontrado arbitrariamente em um ZIP de drivers é executado. O pacote FTDI é procurado na página oficial; caso ela não responda, utiliza-se a versão 2.12.36.20 indicada no catálogo oficial. Bloqueios de rede, certificados não verificáveis e mudanças nos endpoints resultam em falha explícita, nunca em sucesso simulado.

Logs, downloads e `resultado.json` ficam em `%LOCALAPPDATA%\OneClick-UNIVAP\runs\<data-id>`. O botão da interface abre essa pasta. Downloads anteriores ficam disponíveis para diagnóstico e podem ser removidos manualmente após a validação. O CLI instalado permanece em `tools`. Uma instalação concluída de driver significa pacote adicionado ao Windows; a comunicação USB só pode ser validada com uma placa conectada. Se necessário, o log solicita reiniciar o Windows, sem reiniciá-lo automaticamente.

A opção PowerShell `-ExecutionPolicy Bypass` é aplicada somente ao processo filho que executa o recurso incorporado; nenhuma política persistente é alterada. O projeto não fornece certificado de assinatura de código para o executável gerado. Portanto, o Windows pode apresentá-lo como aplicativo de editor desconhecido. O arquivo `.sha256` publicado permite conferir a integridade do download; não substitui uma assinatura de editor.

## Compilação e verificações

Em um runner Windows x64, com .NET Framework e Windows PowerShell 5.1:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File installer/build.ps1
```

O script usa o compilador C# já instalado em `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`, sem restaurar pacotes NuGet. Saídas:

- `docs/downloads/OneClick-UNIVAP-Setup.exe`
- `docs/downloads/OneClick-UNIVAP-Setup.exe.sha256`

O build analisa a sintaxe PowerShell, executa os testes de seleção, rejeição de entrada inválida, backup, preservação e rollback da configuração, compila a interface e roda novamente os testes através do script incorporado no executável. Os testes não acessam a rede, não instalam nada e usam apenas arquivos temporários próprios.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File installer/install.ps1 -SelfTest
$p = Start-Process docs/downloads/OneClick-UNIVAP-Setup.exe -ArgumentList '--self-test' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw 'Falha no teste do executável' }
```

Esses testes validam o empacotamento e a lógica local, não uma instalação completa. Instalação real, disponibilidade dos fornecedores, drivers, comunicação com placas e comportamento do Arduino IDE devem ser homologados em uma máquina Windows de laboratório antes de distribuição em escala. Em especial, o site FTDI bloqueou requisições automatizadas no ambiente de preparação com HTTP 403; esse caso é tratado como falha de download com registro em log.

Referências: [CLI config add](https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_config_add), [Arduino CLI configuração](https://docs.arduino.cc/arduino-cli/configuration), [Arduino IDE releases](https://github.com/arduino/arduino-ide/releases), [Arduino CLI releases](https://github.com/arduino/arduino-cli/releases), [Silicon Labs](https://www.silabs.com/developer-tools/usb-to-uart-bridge-vcp-drivers), [WCH](https://www.wch-ic.com/downloads/CH341SER_ZIP.html), [FTDI](https://ftdichip.com/drivers/vcp-drivers/).
