# Laboratório 2027

Portal de apoio às aulas do **Prof. Bruno Michel Pera**, com azul, branco e vermelho inspirados na identidade da UNIVAP.

**Site:** https://perabru.github.io/univap-laboratorio-2027/

Reúne links oficiais para Cisco Packet Tracer, MySQL Workbench, XAMPP, MongoDB Compass, Android Studio, wiRedPanda e Arduino IDE; quatro planos de ensino de 2027 em PDF; e o OneClick para preparar o ambiente Arduino, ESP32 e Raspberry Pi Pico no Windows.

Os links dos programas abrem as páginas oficiais, onde o aluno escolhe a versão estável atual e o sistema operacional. O MongoDB Compass deve ser aberto pelo menos uma vez pelo usuário que utilizará o programa para inicializar seu cache.

## Planos de ensino

- [CLD I](docs/planos/Plano_de_Ensino_CLD_I_UNIVAP_2027.pdf)
- [CLD II](docs/planos/Plano_de_Ensino_CLD_II_UNIVAP_2027.pdf)
- [Redes](docs/planos/Plano_de_Ensino_Redes_UNIVAP_2027.pdf)
- [Banco de Dados](docs/planos/Plano_de_Ensino_Banco_de_Dados_UNIVAP_2027.pdf)

## Instalador Windows

O executável é compilado pelo GitHub Actions e fica disponível no site e em [Releases](https://github.com/perabru/univap-laboratorio-2027/releases/latest). Leia as instruções e os limites de validação em [installer/README.md](installer/README.md).

O projeto original é https://github.com/perabru/OneClickInstallerEspRasp. Esta versão oferece interface gráfica, seleção de componentes, progresso e registro das etapas. O instalador é específico para Arduino, ESP32, Pico e suas bibliotecas/drivers; os demais programas do portal têm seus próprios instaladores oficiais.

## Publicação

O conteúdo estático está em `docs/`. Cada alteração em `main` compila e testa o instalador em Windows, verifica os PDFs, publica os arquivos no GitHub Pages e cria uma versão para download. O Pages deve usar **GitHub Actions** como origem.

Não há formulário de cadastro, coleta de dados ou dependência de um servidor de aplicação. Este é um material didático do professor. Os nomes dos programas e da instituição pertencem aos respectivos titulares.
