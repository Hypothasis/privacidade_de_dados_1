class HomeController < ApplicationController

  CAMPOS_SENSIVEIS = ['cpf', 'nome']
  SEMI_IDENTIFICADORES = ['localidade', 'data_nascimento']
  CAMPO_SENSIVEL = 'raca_cor'

  HIERARQUIAS = {
    'localidade' => 3,
    'data_nascimento' => 3
  }

  def index
    @statistics = Statistic.find_by(id: 1)
    @cidades = TopCidade.find_by(id: 1)
  end

  def run
    @all_cidades = Hash.new(0)
    file_path = Rails.root.join('public', 'dados_covid.csv')
    k = 2
    l = 2

    # Principais métodos para anonimização
    csv_data = CSV.read(file_path, headers: true)

    Rails.logger.info "Inicializando anonimização"
    csv_data = anonimizar_identificadores_diretos(csv_data)

    Rails.logger.info "Ordenando dados"
    csv_data = ordernar_dados(csv_data)

    Rails.logger.info "Anonimizando e agrupando dados"
    resultado = anonimizar_por_agrupamento_dinamico(csv_data, k, l)

    Rails.logger.info "Calculando dados para Histogramas"
    histograma_data = calcular_histograma_l_diversidade(resultado) # Array 0,4
    precisao = calcular_precisao(resultado)
    pracisao = (precisao * 100).round(2) # Float

    info = get_info(resultado, k, l)
    classes_geradas = info[:grupos_validos] # classes_geradas

    # Histograma
    registro = LHistograma.find_or_initialize_by(id: 1)
    registro.data_1 = histograma_data[1]
    registro.data_2 = histograma_data[2]
    registro.data_3 = histograma_data[3]
    registro.data_4 = histograma_data[4]
    registro.data_5 = histograma_data[5]
    registro.save!
    Rails.logger.info "Registro para histograma l salvo"
    Rails.logger.info "Classes geradas - #{classes_geradas}"
    # Top 5 cidades com mais pessoas
    top_5_cidades = @all_cidades.sort_by { |cidade, count| -count }.first(5)
    top_5_cidades.each do |cidade, contagem|
      # Cria ou atualiza registro no banco
      registro = TopCidade.find_or_initialize_by(nome_cidade: cidade)
      registro.contagem = contagem
      registro.save!
    end
    Rails.logger.info "Salvo top 5 cidades"

    # Calcula top 5 classes de equivalência
    top_k_classes = calcular_histograma_classe_equivalencia(resultado)

    # Salva no banco ou em variável global, conforme sua preferência
    top_k_classes.each_with_index do |(label, count), i|
      registro = KHistograma.find_or_initialize_by(posicao: i + 1)
      registro.nome_classe = label
      registro.contagem = count
      registro.save!
    end

    # Statistics
    statistics = Statistic.find_or_create_by(id: 1)
    statistics.k = k
    statistics.l = l
    statistics.precisao = pracisao
    statistics.classes_geradas = classes_geradas
    statistics.save!

    salvar_csv(resultado, Rails.root.join('public', 'resultado_anonimizado.csv'))

    render plain: "Anonimização concluída com sucesso."

  end

  def baixar_csv
    filepath = Rails.root.join('public', 'resultado_anonimizado.csv')

    if File.exist?(filepath)
      send_file filepath, filename: 'resultado_anonimizado.csv', type: 'text/csv'
    else
      render plain: "Arquivo não encontrado", status: :not_found
    end
  end

  def get
    # Top 5 cidades
    doughnut_estado = TopCidade.order(contagem: :desc).limit(5).pluck(:nome_cidade, :contagem).to_h

    # Histograma l-diversidade
    histograma = LHistograma.find_by(id: 1)
    pie_bar_l = {
      1 => ['1', histograma.data_1],
      2 => ['2', histograma.data_2],
      3 => ['3', histograma.data_3],
      4 => ['4', histograma.data_4],
      5 => ['5', histograma.data_5]
    }

    # Histograma k-anonimato
    k_histograma = KHistograma.order(:posicao).map do |k|
      [k.nome_classe, k.contagem]
    end.to_h

    render json: {
      data: {
        doughnut_estado: doughnut_estado,
        pie_bar_l: pie_bar_l,
        k_histograma: k_histograma
      }
    }
  end

  private

  # Remove identificadores diretos
  def anonimizar_identificadores_diretos(csv_data)
    csv_data.map do |row|
      linha = row.to_h.reject { |k,_| k.nil? }.transform_keys { |k| k.strip }
      CAMPOS_SENSIVEIS.each { |campo| linha[campo] = '***' if linha.key?(campo) }

      # Separar Cidades
      if linha['localidade'].to_s.strip.upcase =~ %r{\A(.+?)/(.+?)/([A-Z]{2})\z}
        cidade = $2.strip
        @all_cidades[cidade] ||= 0
        @all_cidades[cidade] += 1
      end

      linha
    end
  end

  # Ordena por localidade e idade
  def ordernar_dados(csv_data)
    csv_data.sort_by do |pessoa|
      partes = (pessoa['localidade'] || '').split('/')
      partes.fill('', partes.size...3)
      bairro, cidade, estado = partes[0], partes[1], partes[2]
      data_nascimento = Date.strptime(pessoa['data_nascimento'], '%d/%m/%Y') rescue Date.new(1900,1,1)
      [estado, cidade, bairro, data_nascimento]
    end
  end

  def generalizar_localidade(localidade, nivel)
    partes = localidade.to_s.split('/')
    case nivel
    when 0 then localidade
    when 1 then (partes[1..2] || []).join('/')
    when 2 then partes[2] || '*'
    else '*'
    end
  end

  def generalizar_data(data_str, nivel)
    begin
      data = Date.strptime(data_str, '%d/%m/%Y')
    rescue
      return '*'
    end

    case nivel
    when 0 then data.strftime('%d/%m/%Y')
    when 1 then data.strftime('%m/%Y')
    when 2 then data.year.to_s
    else '*'
    end
  end

  def detectar_nivel_generalizacao_data(grupo)
    dias = Set.new
    meses = Set.new
    anos = Set.new

    grupo.each do |registro|
      begin
        data = Date.strptime(registro['data_nascimento'], '%d/%m/%Y')
        dias << data.day
        meses << data.month
        anos << data.year
      rescue
        # Caso data inválida, considere nível máximo de generalização
        return 3
      end
    end

    # Define o nível de generalização conforme variabilidade dos valores
    if anos.size > 1
      3 # ano varia: generalizar tudo
    elsif meses.size > 1
      2 # mês varia: generalizar dia e mês
    elsif dias.size > 1
      1 # dia varia: generalizar só o dia
    else
      0 # data completa igual para todos
    end
  end

  def detectar_nivel_generalizacao_localidade(grupo)
    bairros = Set.new
    cidades = Set.new
    estados = Set.new

    grupo.each do |registro|
      partes = registro['localidade'].to_s.strip.split('/')
      partes.fill('', partes.size...3) # Garante que sempre tenha 3 elementos

      bairro, cidade, estado = partes

      bairros << bairro
      cidades << cidade
      estados << estado

      # Se alguma parte estiver ausente, retorna o nível máximo
      return 3 if bairro.empty? || cidade.empty? || estado.empty?
    end

    if estados.size > 1
      3
    elsif cidades.size > 1
      2
    elsif bairros.size > 1
      1
    else
      0
    end
  end


  def aplicar_generalizacao_individual(row, nivel_localidade, nivel_nascimento)
    nova = row.dup
    nova['localidade'] = generalizar_localidade(row['localidade'], nivel_localidade)
    nova['data_nascimento'] = generalizar_data(row['data_nascimento'], nivel_nascimento)
    nova['nivel_localidade'] = nivel_localidade
    nova['nivel_data_nascimento'] = nivel_nascimento
    nova
  end

  def satisfaz_k_l?(grupo, k, l)
    return false if grupo.size < k
    grupo.map { |r| r[CAMPO_SENSIVEL] }.uniq.size >= l
  end

  # 1 - Separa por bairro e data
  # 2 - Senao se encaixar datas, aumenta o nivel da data
  # 3 -  Senao encaixou aumenta nivel bairro
  # a intenção é formar todo mundo com a mesma cidade e idade
  # se tiver no nivel 3 de cidade, guarda no buffer e tenta encaixar outras pessoas pelo /CE e ano
  # em ultimo caso, aumenta o nivel da data (até o ponto de generalizar 1922 a 1930)
  def anonimizar_por_agrupamento_dinamico(csv_data, k, l)
    buffer = []
    grupos_hash = {}
    resultado = []

    # Agrupar por bairro/cidade/estado
    csv_data.each do |row|
      localidade = row['localidade'].to_s.strip
      if localidade.count('/') == 2
        grupos_hash[localidade] ||= []
        grupos_hash[localidade] << row.to_h
      else
        buffer << row.to_h
      end
    end

    # Reindexar grupos com chave numérica
    grupos_hash = grupos_hash.values.each_with_index.to_h { |pessoas, idx| [idx + 1, pessoas] }

    # Processar cada grupo para tentar generalizar e satisfazer k,l
    grupos_hash.each do |_, grupo|
      next if grupo.size < k

      # Detectar níveis de generalização
      nivel_data = detectar_nivel_generalizacao_data(grupo)
      nivel_localidade = detectar_nivel_generalizacao_localidade(grupo)

      # Calcular intervalo de anos se necessário
      intervalo = nil
      if nivel_data == 3
        anos = grupo.map do |r|
          begin
            Date.strptime(r['data_nascimento'], '%d/%m/%Y').year
          rescue
            nil
          end
        end.compact
        intervalo = anos.max unless anos.empty?
      end

      # Aplicar generalização
      grupo_generalizado = grupo.map do |row|
        linha = aplicar_generalizacao_individual(row, nivel_localidade, nivel_data)
        linha['data_nascimento'] = intervalo if nivel_data == 3 && intervalo
        linha
      end

      # Verificar se o grupo satisfaz k,l
      if satisfaz_k_l?(grupo_generalizado, k, l)
        resultado.concat(grupo_generalizado)
      else
        buffer.concat(grupo)
      end
    end

    # Tratar buffer (pessoas não encaixadas nos grupos)
    unless buffer.empty?
      foi_agregado = false

      (0...HIERARQUIAS['localidade']).each do |nivel_loc|
        (0...HIERARQUIAS['data_nascimento']).each do |nivel_data|
          grupo_generalizado = buffer.map do |row|
            aplicar_generalizacao_individual(row, nivel_loc, nivel_data)
          end

          # Agora reagrupa por [localidade, data_nascimento]
          grupos = grupo_generalizado.group_by { |r| [r['localidade'], r['data_nascimento']] }

          todos_validos = grupos.all? { |_, g| satisfaz_k_l?(g, k, l) }

          if todos_validos
            resultado.concat(grupo_generalizado)
            buffer.clear
            foi_agregado = true
            break
          end
        end
        break if foi_agregado
      end

      unless foi_agregado
        buffer.clear
      end
    end

    resultado
  end

  def calcular_precisao(dados_anonimizados)
    n = dados_anonimizados.size
    return 0.0 if n == 0
    m = SEMI_IDENTIFICADORES.size
    soma = 0

    dados_anonimizados.each do |r|
      SEMI_IDENTIFICADORES.each do |campo|
        nivel = r["nivel_#{campo}"] || 0
        nivel = 2 if r["nivel_#{campo}"] == 3
        soma += nivel.to_f / HIERARQUIAS[campo]
      end
    end

    1 - (soma / (n * m))
  end

  def salvar_csv(dados, output_path)
    CSV.open(output_path, 'w') do |csv|
      csv << dados.first.to_h.keys
      dados.each { |row| csv << row.to_h.values }
    end
  end

  # Info geral
  def get_info(csv_data, k, l)
    grupos = csv_data.chunk { |row| [row['localidade'], row['data_nascimento']] }.to_a
    validos = grupos.select { |_, grupo| satisfaz_k_l?(grupo, k, l) }
    {
      total_registros: csv_data.size,
      total_grupos: grupos.size,
      grupos_validos: validos.size,
      registros_finais: validos.flat_map(&:last).size
    }
  end

  # Calcula histograma l-diversidade
  def calcular_histograma_l_diversidade(csv_data)
    grupos = csv_data.group_by { |row| [row['localidade'], row['data_nascimento']] }
    histograma = Hash.new(0)
    grupos.each do |_, grupo|
      num = grupo.map { |r| r[CAMPO_SENSIVEL] }.uniq.size
      histograma[[num,5].min] += 1
    end
    (1..5).each { |i| histograma[i] ||= 0 }
    histograma
  end

  def calcular_histograma_classe_equivalencia(csv_data)
    # Agrupar por localidade e data de nascimento
    grupos = csv_data.group_by { |row| [row['localidade'], row['data_nascimento']] }

    # Contar número de registros por grupo e formatar a label com nível
    grupos_transformados = grupos.map do |(localidade, data), pessoas|
      label = "#{localidade} #{data}"
      count = pessoas.size
      [label, count]
    end

    # Ordenar pelas maiores classes e pegar os 5 primeiros
    top_5 = grupos_transformados.sort_by { |_, count| -count }.first(5)
    top_5
  end

  def get_histograma_data(histograma_data)
    Rails.logger.info "\nHistograma de classes por diversidade de raças:"
    histograma_data.sort.each do |num_raças, qtd_classes|
      Rails.logger.info "#{num_raças} raças distintas: #{qtd_classes} classes"
    end
  end
end
